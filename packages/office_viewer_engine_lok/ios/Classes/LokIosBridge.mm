#import "LokIosBridge.h"

#include <cstdlib>
#include <cstring>
#include <span>
#include <string>

#import <Foundation/Foundation.h>

#define DISABLE_DYNLOADING 1
#ifndef IOS
#define IOS IOS
#endif

#import <COKit/COKit.hxx>
#import <COKit/COKitInit.h>

namespace {

COKit* gOffice = nullptr;

char* DupCString(const std::string& s) {
  if (s.empty()) {
    return nullptr;
  }
  char* out = static_cast<char*>(std::malloc(s.size() + 1));
  if (out == nullptr) {
    return nullptr;
  }
  std::memcpy(out, s.data(), s.size() + 1);
  return out;
}

COKitDocument* AsDoc(intptr_t doc) {
  return reinterpret_cast<COKitDocument*>(doc);
}

}  // namespace

extern "C" intptr_t office_viewer_lok_ios_init(const char* resourcePath,
                                               const char* userProfilePath) {
  @autoreleasepool {
    if (gOffice != nullptr) {
      return reinterpret_cast<intptr_t>(gOffice);
    }

    // On iOS, sal/rtl/bootstrap.cxx hard-wires $APP_DATA_DIR to
    // NSBundle.mainBundle — LO files must live at Runner.app root (see
    // example/ios Podfile copy phase). Optional resourcePath is only used
    // to locate ICU.dat when it is not already at the app root.
    NSString* appRoot = [[NSBundle mainBundle] bundlePath];
    NSString* res = appRoot;
    if (resourcePath != nullptr && resourcePath[0] != '\0') {
      NSString* candidate = [NSString stringWithUTF8String:resourcePath];
      NSString* probe =
          [candidate stringByAppendingPathComponent:@"services.rdb"];
      if ([[NSFileManager defaultManager] fileExistsAtPath:probe]) {
        res = candidate;
      }
    }

    NSString* icuDat = [appRoot stringByAppendingPathComponent:@"ICU.dat"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:icuDat]) {
      NSString* alt =
          [res stringByAppendingPathComponent:@"ICU.dat"];
      if ([[NSFileManager defaultManager] fileExistsAtPath:alt]) {
        icuDat = alt;
      } else {
        NSArray<NSString*>* matches =
            [[NSFileManager defaultManager] contentsOfDirectoryAtPath:appRoot
                                                                error:nil];
        for (NSString* name in matches) {
          if ([name hasPrefix:@"icudt"] && [name hasSuffix:@".dat"]) {
            icuDat = [appRoot stringByAppendingPathComponent:name];
            break;
          }
        }
      }
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:icuDat]) {
      setenv("LIBREOFFICE_ICU_DATA", [icuDat UTF8String], 1);
    } else {
      NSLog(@"office_viewer_lok_ios_init: ICU.dat missing under %@", appRoot);
    }

    NSString* services =
        [appRoot stringByAppendingPathComponent:@"services.rdb"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:services]) {
      NSLog(@"office_viewer_lok_ios_init: services.rdb missing under %@ — "
            @"Podfile copy phase did not run",
            appRoot);
      return 0;
    }

    // Pass main-bundle path explicitly. nullptr install path makes
    // lo_initialize() derive the path from &lo_initialize (inside the plugin
    // framework) → looks for rc under …/office_viewer_engine_lok.framework.
    //
    // Do NOT pass a user-profile URL: lo_initialize then sets
    // BRAND_BASE_DIR=installPath/.. (the app's parent container), and
    // services/share resolve outside Runner.app → bootstrap/render errors
    // where the document should appear. Match upstream ios/UnitTest:
    // cok_init_2(install, nullptr); profile uses HOME/$SYSUSERHOME from rc.
    if (userProfilePath != nullptr && userProfilePath[0] != '\0') {
      setenv("HOME", userProfilePath, 1);
    }
    // Viewer-only: quieter logs (missing spell/autocorr) and no crash recovery UI.
    setenv("SAL_LOG", "-WARN", 0);
    setenv("OOO_DISABLE_RECOVERY", "1", 0);
    const char* installPath = [appRoot UTF8String];
    NSLog(@"office_viewer_lok_ios_init: installPath=%@ home=%s", appRoot,
          getenv("HOME") ? getenv("HOME") : "(null)");
    try {
      gOffice = cok_init_2(installPath, nullptr);
    } catch (const std::exception& e) {
      NSLog(@"office_viewer_lok_ios_init: cok_init_2 exception: %s", e.what());
      gOffice = nullptr;
    } catch (...) {
      NSLog(@"office_viewer_lok_ios_init: cok_init_2 unknown/uno exception");
      gOffice = nullptr;
    }
    if (gOffice == nullptr) {
      NSLog(@"office_viewer_lok_ios_init: cok_init_2 failed");
      return 0;
    }
    return reinterpret_cast<intptr_t>(gOffice);
  }
}

extern "C" int office_viewer_lok_ios_is_ready(void) {
  return gOffice != nullptr ? 1 : 0;
}

extern "C" intptr_t office_viewer_lok_ios_office_ptr(void) {
  return reinterpret_cast<intptr_t>(gOffice);
}

extern "C" intptr_t office_viewer_lok_ios_document_load(intptr_t office,
                                                       const char* url) {
  return office_viewer_lok_ios_document_load_with_options(office, url, nullptr);
}

extern "C" intptr_t office_viewer_lok_ios_document_load_with_options(
    intptr_t office, const char* url, const char* options) {
  auto* kit = reinterpret_cast<COKit*>(office);
  if (kit == nullptr || url == nullptr) {
    return 0;
  }
  // Soft-fail UNO/C++ exceptions so Dart can surface PasswordRequired /
  // Corrupt errors instead of freezing under lldb. Hard abort() still kills.
  try {
    COKitDocument* doc = (options != nullptr && options[0] != '\0')
                             ? kit->documentLoadWithOptions(url, options)
                             : kit->documentLoad(url);
    return reinterpret_cast<intptr_t>(doc);
  } catch (const std::exception& e) {
    NSLog(@"office_viewer_lok_ios_document_load: %s", e.what());
    return 0;
  } catch (...) {
    NSLog(@"office_viewer_lok_ios_document_load: unknown exception url=%s",
          url);
    return 0;
  }
}

extern "C" void office_viewer_lok_ios_document_destroy(intptr_t doc) {
  delete AsDoc(doc);
}

extern "C" char* office_viewer_lok_ios_get_error(intptr_t office) {
  auto* kit = reinterpret_cast<COKit*>(office);
  if (kit == nullptr) {
    return nullptr;
  }
  return DupCString(kit->getError());
}

extern "C" void office_viewer_lok_ios_free_error(char* err) {
  std::free(err);
}

extern "C" int office_viewer_lok_ios_get_document_type(intptr_t doc) {
  auto* d = AsDoc(doc);
  if (d == nullptr) {
    return static_cast<int>(COKitDocumentType::OTHER);
  }
  return static_cast<int>(d->getDocumentType());
}

extern "C" int office_viewer_lok_ios_get_parts(intptr_t doc) {
  auto* d = AsDoc(doc);
  return d == nullptr ? 0 : d->getParts();
}

extern "C" void office_viewer_lok_ios_set_part(intptr_t doc, int partIndex) {
  auto* d = AsDoc(doc);
  if (d == nullptr) {
    return;
  }
  // Impress/Draw: setPart wants the page GUID ("{…}"), not a decimal index.
  // Passing "1"/"2" leaves the current part unchanged → every tile shows slide 0.
  // getPartId(n, 0) returns that GUID (mode 0 = standard slides); for Calc/Writer
  // it returns the index in decimal form, so one path works for all types.
  try {
    if (d->getDocumentType() == COKitDocumentType::PRESENTATION ||
        d->getDocumentType() == COKitDocumentType::DRAWING) {
      d->setPartMode(COKitPartMode::SLIDES);
    }
    std::string id = d->getPartId(partIndex, /*nMode=*/0);
    if (id.empty()) {
      id = std::to_string(partIndex);
    }
    d->setPart(id.c_str());
  } catch (...) {
    NSLog(@"office_viewer_lok_ios_set_part: failed for part %d", partIndex);
  }
}

extern "C" char* office_viewer_lok_ios_get_part_name(intptr_t doc,
                                                    int partIndex) {
  auto* d = AsDoc(doc);
  if (d == nullptr) {
    return nullptr;
  }
  return DupCString(d->getPartName(partIndex));
}

extern "C" char* office_viewer_lok_ios_get_part_page_rectangles(intptr_t doc) {
  auto* d = AsDoc(doc);
  if (d == nullptr) {
    return nullptr;
  }
  try {
    // CPiOS COKitDocument API uses getWriterPageRectangles() (Writer page
    // extents). Android LOK C API historically named this getPartPageRectangles;
    // keep the exported C symbol for Dart FFI, map to the COKit name here.
    return DupCString(d->getWriterPageRectangles());
  } catch (...) {
    NSLog(@"office_viewer_lok_ios_get_part_page_rectangles: failed");
    return nullptr;
  }
}

extern "C" void office_viewer_lok_ios_get_document_size(intptr_t doc,
                                                       int64_t* widthTwips,
                                                       int64_t* heightTwips) {
  auto* d = AsDoc(doc);
  if (d == nullptr || widthTwips == nullptr || heightTwips == nullptr) {
    return;
  }
  const COKitSize size = d->getDocumentSize();
  *widthTwips = size.nWidth;
  *heightTwips = size.nHeight;
}

extern "C" void office_viewer_lok_ios_initialize_for_rendering(
    intptr_t doc, const char* args) {
  auto* d = AsDoc(doc);
  if (d == nullptr) {
    return;
  }
  try {
    d->initializeForRendering(args == nullptr ? "{}" : args);
  } catch (const std::exception& e) {
    NSLog(@"office_viewer_lok_ios_initialize_for_rendering: %s", e.what());
  } catch (...) {
    NSLog(@"office_viewer_lok_ios_initialize_for_rendering: unknown exception");
  }
}

extern "C" int office_viewer_lok_ios_get_tile_mode(intptr_t doc) {
  auto* d = AsDoc(doc);
  if (d == nullptr) {
    return 0;
  }
  return d->getTileMode() == COKitTileMode::BGRA ? 1 : 0;
}

extern "C" void office_viewer_lok_ios_paint_tile(intptr_t doc, uint8_t* buffer,
                                                 int canvasWidth,
                                                 int canvasHeight, int tilePosX,
                                                 int tilePosY, int tileWidth,
                                                 int tileHeight) {
  auto* d = AsDoc(doc);
  if (d == nullptr || buffer == nullptr) {
    return;
  }
  const size_t nbytes =
      static_cast<size_t>(canvasWidth) * static_cast<size_t>(canvasHeight) * 4u;
  // Soft-fail UNO/C++ exceptions so one bad tile does not tear down the
  // isolate. Hard asserts (abort) still kill the process — those need process
  // isolation; until then leave a transparent tile.
  try {
    std::memset(buffer, 0, nbytes);
    d->paintTile(std::span<unsigned char>(buffer, nbytes), canvasWidth,
                 canvasHeight, tilePosX, tilePosY, tileWidth, tileHeight);
  } catch (...) {
    std::memset(buffer, 0, nbytes);
    NSLog(@"office_viewer_lok_ios_paint_tile: exception (tile cleared)");
  }
}

// Used when LOK_HOME_IOS is not installed — keeps the Swift plugin linkable.
#import "LokIosBridge.h"
#include <cstdlib>

extern "C" intptr_t office_viewer_lok_ios_init(const char*, const char*) { return 0; }
extern "C" int office_viewer_lok_ios_is_ready(void) { return 0; }
extern "C" intptr_t office_viewer_lok_ios_office_ptr(void) { return 0; }
extern "C" intptr_t office_viewer_lok_ios_document_load(intptr_t, const char*) { return 0; }
extern "C" intptr_t office_viewer_lok_ios_document_load_with_options(intptr_t, const char*,
                                                                    const char*) {
  return 0;
}
extern "C" void office_viewer_lok_ios_document_destroy(intptr_t) {}
extern "C" char* office_viewer_lok_ios_get_error(intptr_t) { return nullptr; }
extern "C" void office_viewer_lok_ios_free_error(char* err) { free(err); }
extern "C" int office_viewer_lok_ios_get_document_type(intptr_t) { return 4; }
extern "C" int office_viewer_lok_ios_get_parts(intptr_t) { return 0; }
extern "C" void office_viewer_lok_ios_set_part(intptr_t, int) {}
extern "C" char* office_viewer_lok_ios_get_part_name(intptr_t, int) { return nullptr; }
extern "C" char* office_viewer_lok_ios_get_part_page_rectangles(intptr_t) {
  return nullptr;
}
extern "C" void office_viewer_lok_ios_get_document_size(intptr_t, int64_t* w, int64_t* h) {
  if (w) *w = 0;
  if (h) *h = 0;
}
extern "C" void office_viewer_lok_ios_initialize_for_rendering(intptr_t, const char*) {}
extern "C" int office_viewer_lok_ios_get_tile_mode(intptr_t) { return 0; }
extern "C" void office_viewer_lok_ios_paint_tile(intptr_t, uint8_t*, int, int, int, int, int,
                                                 int) {}

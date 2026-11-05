#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Initialize the iOS static LOK kit. Returns an opaque office pointer
/// as intptr, or 0 on failure. [resourcePath] is the bundled LOK
/// resource directory (contains udkapi.rdb, share/, program/, ICU.dat, …).
/// [userProfilePath] is a filesystem path for the user profile directory.
intptr_t office_viewer_lok_ios_init(const char* resourcePath,
                                    const char* userProfilePath);

int office_viewer_lok_ios_is_ready(void);
intptr_t office_viewer_lok_ios_office_ptr(void);

intptr_t office_viewer_lok_ios_document_load(intptr_t office, const char* url);
/// Same as document_load; [options] is LOK FilterOptions JSON (Password, …).
intptr_t office_viewer_lok_ios_document_load_with_options(intptr_t office,
                                                         const char* url,
                                                         const char* options);
void office_viewer_lok_ios_document_destroy(intptr_t doc);
char* office_viewer_lok_ios_get_error(intptr_t office);
void office_viewer_lok_ios_free_error(char* err);

int office_viewer_lok_ios_get_document_type(intptr_t doc);
int office_viewer_lok_ios_get_parts(intptr_t doc);
void office_viewer_lok_ios_set_part(intptr_t doc, int partIndex);
char* office_viewer_lok_ios_get_part_name(intptr_t doc, int partIndex);

void office_viewer_lok_ios_get_document_size(intptr_t doc, int64_t* widthTwips,
                                            int64_t* heightTwips);
void office_viewer_lok_ios_initialize_for_rendering(intptr_t doc,
                                                   const char* args);

/// Tile pixel order: 0 = RGBA, 1 = BGRA.
int office_viewer_lok_ios_get_tile_mode(intptr_t doc);

void office_viewer_lok_ios_paint_tile(intptr_t doc, uint8_t* buffer,
                                     int canvasWidth, int canvasHeight,
                                     int tilePosX, int tilePosY, int tileWidth,
                                     int tileHeight);

#ifdef __cplusplus
}
#endif

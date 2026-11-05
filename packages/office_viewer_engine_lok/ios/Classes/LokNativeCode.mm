// Instantiates lo_get_factory_map / lo_get_constructor_map for DISABLE_DYNLOADING.
// Symbols resolve from the CPiOS static archives linked via -filelist.

#define DISABLE_DYNLOADING 1
#ifndef IOS
#define IOS IOS
#endif

extern "C" {
#include "native-code.h"
}

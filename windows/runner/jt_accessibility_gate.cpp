// JT: WP2.11 - accessibility gate for the Flutter view (crash jt.6.1).
// See jt_accessibility_gate.h and CUSTOMIZING.md ("Toegankelijkheid op Windows").
#include "jt_accessibility_gate.h"

#include <commctrl.h>
#include <uiautomation.h>

#include <cstdlib>
#include <cstring>

namespace {

constexpr UINT_PTR kJtGateSubclassId = 0x4A54;  // "JT"

// Once a screen reader was seen, Flutter has semantics on for good; stop
// checking and let everything through.
bool g_allowed = false;

bool JtNarratorRunning() {
  DWORD value = 0;
  DWORD size = sizeof(value);
  return RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Narrator\\NoRoam",
                      L"RunningState", RRF_RT_REG_DWORD, nullptr, &value,
                      &size) == ERROR_SUCCESS &&
         value != 0;
}

bool JtAccessibilityWanted() {
  char* env = nullptr;
  size_t len = 0;
  if (_dupenv_s(&env, &len, "JT_ACCESSIBILITY") == 0 && env != nullptr) {
    bool on = std::strcmp(env, "1") == 0;
    free(env);
    if (on) {
      return true;
    }
  }
  BOOL screen_reader = FALSE;
  if (SystemParametersInfoW(SPI_GETSCREENREADER, 0, &screen_reader, 0) &&
      screen_reader) {
    return true;
  }
  return JtNarratorRunning();
}

LRESULT CALLBACK JtGateProc(HWND hwnd, UINT message, WPARAM wparam,
                            LPARAM lparam, UINT_PTR id, DWORD_PTR) {
  if (message == WM_GETOBJECT && !g_allowed) {
    // Same object-id test as the engine (flutter_window.cc OnGetObject).
    DWORD obj_id = static_cast<DWORD>(static_cast<DWORD_PTR>(lparam));
    if (obj_id == static_cast<DWORD>(UiaRootObjectId) ||
        obj_id == static_cast<DWORD>(OBJID_CLIENT)) {
      if (!JtAccessibilityWanted()) {
        return DefWindowProcW(hwnd, message, wparam, lparam);
      }
      g_allowed = true;
    }
  }
  if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(hwnd, JtGateProc, id);
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

}  // namespace

void JtInstallAccessibilityGate(HWND flutter_view) {
  if (flutter_view != nullptr) {
    SetWindowSubclass(flutter_view, JtGateProc, kJtGateSubclassId, 0);
  }
}

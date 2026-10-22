// JT: WP2.11 - accessibility gate for the Flutter view (crash jt.6.1).
#ifndef RUNNER_JT_ACCESSIBILITY_GATE_H_
#define RUNNER_JT_ACCESSIBILITY_GATE_H_

#include <windows.h>

// The Flutter engine (3.35.7) turns semantics on for the first WM_GETOBJECT
// (MSAA OBJID_CLIENT or UIA root) from *any* accessibility client, and then
// keeps them on. With semantics on, the Windows AccessibilityBridge can crash
// in CreateRemoveReparentedNodesUpdate (flutter/flutter#175041, no upstream
// fix). This gate only lets those requests reach Flutter when a screen
// reader is active (SPI_GETSCREENREADER, a running Narrator) or when the user
// opts in with the environment variable JT_ACCESSIBILITY=1. Other clients get
// the default Windows answer, so semantics stay off for them.
void JtInstallAccessibilityGate(HWND flutter_view);

#endif  // RUNNER_JT_ACCESSIBILITY_GATE_H_

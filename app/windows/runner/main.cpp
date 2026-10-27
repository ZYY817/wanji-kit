#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  // Clamp the initial size to the work area: 1280x720 DIP overflows on
  // small / high-scale laptops (e.g. 1366x768 at 125%). SPI_GETWORKAREA
  // returns physical px; divide by the DPI scale to get DIPs, then min().
  RECT work{0, 0, 0, 0};
  ::SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
  const double dip_scale = ::GetDpiForSystem() / 96.0;
  const int max_w = static_cast<int>((work.right - work.left) / dip_scale) - 40;
  const int max_h = static_cast<int>((work.bottom - work.top) / dip_scale) - 40;
  const int init_w = max_w > 0 ? (std::min)(1280, max_w) : 1280;
  const int init_h = max_h > 0 ? (std::min)(720, max_h) : 720;
  Win32Window::Size size(init_w, init_h);
  if (!window.Create(L"\u8FD0\u884C\u5E93\u4F53\u68C0 \u00B7 ZYY817", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}

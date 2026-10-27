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
  // Initial size: ~72% of work-area width, ~16:10-ish, capped and
  // centered - looks deliberate on any screen instead of hugging
  // the top-left corner. SPI_GETWORKAREA is physical px; /DPI = DIPs.
  RECT work{0, 0, 0, 0};
  ::SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
  const double dip_scale = ::GetDpiForSystem() / 96.0;
  const int work_w = static_cast<int>((work.right - work.left) / dip_scale);
  const int work_h = static_cast<int>((work.bottom - work.top) / dip_scale);
  const int max_w = work_w - 80, max_h = work_h - 80;
  int init_w = max_w > 0 ? (std::min)(1360,
      (std::max)(980, static_cast<int>(work_w * 0.72))) : 1280;
  init_w = (std::min)(init_w, max_w > 0 ? max_w : init_w);
  int init_h = static_cast<int>(init_w * 0.60);
  init_h = max_h > 0 ? (std::min)(init_h, max_h) : init_h;
  Win32Window::Point origin(
      (std::max)(0, (work_w - init_w) / 2),
      (std::max)(0, (work_h - init_h) / 2));
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

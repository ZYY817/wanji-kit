#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // "wanji/window": the in-app caption buttons call native window ops.
  // hwnd is taken directly from GetHandle(); Dart never passes it.
  const HWND hwnd = GetHandle();
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "wanji/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this, hwnd](const flutter::MethodCall<flutter::EncodableValue>& call,
                   std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                       result) {
        const std::string& method = call.method_name();
        if (method == "minimize") {
          ::ShowWindow(hwnd, SW_MINIMIZE);
          result->Success();
        } else if (method == "toggleMaximize") {
          ::ShowWindow(hwnd, ::IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
          result->Success();
        } else if (method == "isMaximized") {
          result->Success(flutter::EncodableValue(::IsZoomed(hwnd) == TRUE));
        } else if (method == "close") {
          ::PostMessage(hwnd, WM_CLOSE, 0, 0);
          result->Success();
        } else if (method == "setCaptionExclusion") {
          // Dart reports the controls cluster left edge (DIP); points right
          // of it in the caption strip stay HTCLIENT so buttons get input.
          const auto* d = std::get_if<double>(call.arguments());
          const auto* i32 = std::get_if<int32_t>(call.arguments());
          const auto* i64 = std::get_if<int64_t>(call.arguments());
          if (d != nullptr) {
            SetCaptionExclusionLeft(*d);
          } else if (i32 != nullptr) {
            SetCaptionExclusionLeft(static_cast<double>(*i32));
          } else if (i64 != nullptr) {
            SetCaptionExclusionLeft(static_cast<double>(*i64));
          }
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;

    case WM_SIZE:
      // Dart's AppLifecycleListener never delivers 'hidden' on Windows
      // minimize (engine only emits inactive); forward the real window
      // state so the animation ticker can truly stop while minimized.
      if (window_channel_) {
        const char* state = nullptr;
        if (wparam == SIZE_MINIMIZED) {
          state = "minimized";
        } else if (wparam == SIZE_RESTORED || wparam == SIZE_MAXIMIZED) {
          state = "restored";
        }
        if (state != nullptr) {
          window_channel_->InvokeMethod(
              "windowState",
              std::make_unique<flutter::EncodableValue>(
                  flutter::EncodableValue(state)));
        }
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

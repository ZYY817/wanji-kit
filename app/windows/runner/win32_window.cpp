#include "win32_window.h"

#include <commctrl.h>
#include <dwmapi.h>
#include <flutter_windows.h>
#include <windowsx.h>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE_BEFORE_20H1
#define DWMWA_USE_IMMERSIVE_DARK_MODE_BEFORE_20H1 19
#endif
#ifndef DWMWA_BORDER_COLOR
#define DWMWA_BORDER_COLOR 34
#endif
#ifndef DWMWA_CAPTION_COLOR
#define DWMWA_CAPTION_COLOR 35
#endif
#ifndef DWMWA_TEXT_COLOR
#define DWMWA_TEXT_COLOR 36
#endif
#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_NCCALCSIZE:
      // Truly borderless: the client area covers the whole window rect.
      // WS_THICKFRAME is kept, so edge resizing and Aero Snap still work;
      // Windows just stops drawing any non-client area.
      if (wparam == TRUE) {
        auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
        // A maximized borderless window bleeds a 1px system frame line at
        // the top edge; extend the client 1px upward to cover it.
        if (IsZoomed(hwnd)) {
          params->rgrc[0].top -= 1;
        }
      }
      return 0;

    case WM_NCHITTEST:
      return HitTestForScreenPoint(hwnd, lparam);

    case WM_GETMINMAXINFO: {
      // Enforce the 890x560 minimum layout (DIP -> physical px via DPI).
      auto info = reinterpret_cast<MINMAXINFO*>(lparam);
      const UINT dpi = GetDpiForWindow(hwnd);
      info->ptMinTrackSize.x = MulDiv(890, dpi, 96);
      info->ptMinTrackSize.y = MulDiv(560, dpi, 96);
      // A borderless window maximizes over the whole screen (covering the
      // taskbar); clamp ptMaxSize / ptMaxPosition to the monitor work area.
      HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
      MONITORINFO mi{sizeof(mi)};
      if (GetMonitorInfo(monitor, &mi)) {
        info->ptMaxPosition.x = mi.rcWork.left - mi.rcMonitor.left;
        info->ptMaxPosition.y = mi.rcWork.top - mi.rcMonitor.top;
        info->ptMaxSize.x = mi.rcWork.right - mi.rcWork.left;
        info->ptMaxSize.y = mi.rcWork.bottom - mi.rcWork.top;
      }
      return 0;
    }

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

LRESULT Win32Window::HitTestForScreenPoint(HWND hwnd,
                                           LPARAM lparam) const noexcept {
  // With WM_NCCALCSIZE -> 0, DefWindowProc reports HTCLIENT everywhere,
  // so the sizing-border hits are computed manually here. Priority:
  //   1. controls cluster in the strip  -> HTCLIENT (buttons/pill input)
  //   2. resize borders + corners       -> HTTOP/HTLEFT/...
  //   3. rest of the top strip          -> HTCAPTION (drag/dbl-click)
  //   4. everything else                -> HTCLIENT
  // A zoomed window disables drag/resize entirely (all client).
  if (IsZoomed(hwnd)) {
    return HTCLIENT;
  }
  RECT wr;
  GetWindowRect(hwnd, &wr);
  const int sx = GET_X_LPARAM(lparam);  // screen coords
  const int sy = GET_Y_LPARAM(lparam);
  POINT pt = {sx, sy};
  ScreenToClient(hwnd, &pt);            // client coords == physical px
  const UINT dpi = GetDpiForWindow(hwnd);
  const int caption_px = MulDiv(kCaptionHeightDip, dpi, 96);
  const int client_w = wr.right - wr.left;
  const double excl_dip =
      caption_excl_left_dip_ >= 0
          ? caption_excl_left_dip_
          : client_w * 96.0 / dpi - 250.0;  // fallback: reserve right end
  const int excl_px =
      MulDiv(static_cast<int>(excl_dip + 0.5), dpi, 96);
  // 1) controls cluster (right of the pill's left edge, inside strip)
  if (pt.y >= 0 && pt.y < caption_px && pt.x >= excl_px) {
    return HTCLIENT;
  }
  // 2) resize borders (~6px) + corner grab zones (~14px)
  const int border = MulDiv(6, dpi, 96);
  const int corner = MulDiv(14, dpi, 96);
  const bool on_left = sx >= wr.left && sx < wr.left + border;
  const bool on_right = sx >= wr.right - border && sx < wr.right;
  const bool on_top = sy >= wr.top && sy < wr.top + border;
  const bool on_bottom = sy >= wr.bottom - border && sy < wr.bottom;
  if (on_top) {
    if (sx < wr.left + corner) return HTTOPLEFT;
    if (sx >= wr.right - corner) return HTTOPRIGHT;
    return HTTOP;
  }
  if (on_bottom) {
    if (sx < wr.left + corner) return HTBOTTOMLEFT;
    if (sx >= wr.right - corner) return HTBOTTOMRIGHT;
    return HTBOTTOM;
  }
  if (on_left) return HTLEFT;
  if (on_right) return HTRIGHT;
  // 3) caption drag zone (rest of the strip)
  if (pt.y >= 0 && pt.y < caption_px) {
    return HTCAPTION;
  }
  // 4) client
  return HTCLIENT;
}

// static
LRESULT CALLBACK Win32Window::ChildViewSubclassProc(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam,
    UINT_PTR subclass_id, DWORD_PTR ref_data) {
  switch (message) {
    case WM_NCHITTEST: {
      auto* that = reinterpret_cast<Win32Window*>(ref_data);
      if (that != nullptr && that->window_handle_ != nullptr) {
        // The frame decides what this screen point is. Client zones keep
        // HTCLIENT so Flutter receives pointer input; for non-client zones
        // HTTRANSPARENT makes Windows re-run the hit test on the frame
        // underneath, where the normal WM_NCHITTEST path then yields
        // HTCAPTION / border codes and owns the drag/resize input.
        const LRESULT hit =
            that->HitTestForScreenPoint(that->window_handle_, lparam);
        return hit == HTCLIENT ? HTCLIENT : HTTRANSPARENT;
      }
      break;
    }
    case WM_NCDESTROY:
      RemoveWindowSubclass(hwnd, &Win32Window::ChildViewSubclassProc,
                           subclass_id);
      break;
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (child_content_ != nullptr) {
    if (IsWindow(child_content_)) {
      RemoveWindowSubclass(child_content_, &Win32Window::ChildViewSubclassProc,
                           kChildViewSubclassId);
    }
    child_content_ = nullptr;
  }
  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  if (child_content_ != nullptr && child_content_ != content &&
      IsWindow(child_content_)) {
    RemoveWindowSubclass(child_content_, &Win32Window::ChildViewSubclassProc,
                         kChildViewSubclassId);
  }
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  // The child covers the whole client area, so without this a real mouse
  // would hit-test the child (always HTCLIENT) and the frame's borderless
  // drag/resize zones would be unreachable. The subclass forwards only the
  // non-client zones back to the frame via HTTRANSPARENT.
  SetWindowSubclass(content, &Win32Window::ChildViewSubclassProc,
                    kChildViewSubclassId, reinterpret_cast<DWORD_PTR>(this));

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  // Borderless window: the non-client area is gone entirely, so the DWM
  // caption attributes no longer paint. Keep dark=off + cream border so the
  // 1px DWM outer edge blends in, and explicitly request round corners on
  // Win11 (borderless can otherwise fall back to square).
  BOOL dark = FALSE;
  DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                        &dark, sizeof(dark));
  DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE_BEFORE_20H1,
                        &dark, sizeof(dark));
  const COLORREF caption = RGB(0xF0, 0xEC, 0xE3);  // measured top-strip avg
  const COLORREF text = RGB(0x1A, 0x18, 0x15);     // K.ink
  const COLORREF border = RGB(0xF0, 0xEC, 0xE3);   // same color, no seam
  DwmSetWindowAttribute(window, DWMWA_CAPTION_COLOR, &caption, sizeof(caption));
  DwmSetWindowAttribute(window, DWMWA_TEXT_COLOR, &text, sizeof(text));
  DwmSetWindowAttribute(window, DWMWA_BORDER_COLOR, &border, sizeof(border));
  const int round = 2;  // DWMWCP_ROUND
  DwmSetWindowAttribute(window, DWMWA_WINDOW_CORNER_PREFERENCE,
                        &round, sizeof(round));
}

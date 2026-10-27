#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// A class abstraction for a high DPI-aware Win32 Window. Intended to be
// inherited from by classes that wish to specialize with custom
// rendering and input handling
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // Creates a win32 window with |title| that is positioned and sized using
  // |origin| and |size|. New windows are created on the default monitor. Window
  // sizes are specified to the OS in physical pixels, hence to ensure a
  // consistent size this function will scale the inputted width and height as
  // as appropriate for the default monitor. The window is invisible until
  // |Show| is called. Returns true if the window was created successfully.
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // Show the current window. Returns true if the window was successfully shown.
  bool Show();

  // Release OS resources associated with window.
  void Destroy();

  // Inserts |content| into the window tree.
  void SetChildContent(HWND content);

  // Returns the backing Window handle to enable clients to set icon and other
  // window properties. Returns nullptr if the window has been destroyed.
  HWND GetHandle();

  // If true, closing this window will quit the application.
  void SetQuitOnClose(bool quit_on_close);

  // Return a RECT representing the bounds of the current client area.
  RECT GetClientArea();

  // Left edge (logical px) of the top-strip interactive controls cluster:
  // points right of it never report HTCAPTION so window buttons and the
  // language pill receive normal pointer input. Reported from Dart via
  // MethodChannel once layout completes.
  void SetCaptionExclusionLeft(double dip) { caption_excl_left_dip_ = dip; }

 protected:
  // Processes and route salient window messages for mouse handling,
  // size change and DPI. Delegates handling of these to member overloads that
  // inheriting classes can handle.
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // Called when CreateAndShow is called, allowing subclass window-related
  // setup. Subclasses should return false if setup fails.
  virtual bool OnCreate();

  // Called when Destroy is called.
  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  // OS callback called by message pump. Handles the WM_NCCREATE message which
  // is passed when the non-client area is being created and enables automatic
  // non-client DPI scaling so that the non-client area automatically
  // responds to changes in DPI. All other messages are handled by
  // MessageHandler.
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // Retrieves a class instance pointer for |window|
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // Computes the non-client hit test code (HTCAPTION / HTLEFT / HTCLIENT /
  // ...) that this borderless window reports for the screen point encoded
  // in |lparam| (as in WM_NCHITTEST). |hwnd| must be the top-level frame.
  // Shared by the frame's own WM_NCHITTEST handler and by the FlutterView
  // child-window subclass, so both always agree on which zones are client.
  LRESULT HitTestForScreenPoint(HWND hwnd, LPARAM lparam) const noexcept;

  // Subclass proc installed on the FlutterView child window. The child
  // covers the whole client area, so a real mouse sends WM_NCHITTEST to
  // the child, not the frame: for points inside non-client zones (caption
  // strip / resize edges) the proc returns HTTRANSPARENT, which makes
  // Windows re-issue the hit test to the frame underneath, whose existing
  // WM_NCHITTEST then owns drag/resize. Client zones answer HTCLIENT so
  // Flutter keeps pointer input.
  static LRESULT CALLBACK ChildViewSubclassProc(
      HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam,
      UINT_PTR subclass_id, DWORD_PTR ref_data);

  // Update the window frame's theme to match the system theme.
  static void UpdateTheme(HWND const window);

  // uIdSubclass used for the SetWindowSubclass call on child_content_.
  static constexpr UINT_PTR kChildViewSubclassId = 0x574A54;  // 'WJT'

  // Borderless caption-strip height (logical px) used for hit testing.
  static constexpr int kCaptionHeightDip = 40;

  bool quit_on_close_ = false;

  // Left edge (logical px) of the top-strip controls cluster. Negative =
  // not reported yet -> hit test falls back to reserving ~250dip at the
  // strip's right end so the buttons stay clickable.
  double caption_excl_left_dip_ = -1.0;

  // window handle for top level window.
  HWND window_handle_ = nullptr;

  // window handle for hosted content.
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_

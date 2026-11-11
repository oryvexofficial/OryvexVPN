#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Every child the app starts (the core, Tor's transports, Psiphon) joins this job, and the job
// kills them all when the last handle to it closes: the app exiting, or crashing, takes the
// core with it. Failure is harmless (an outer job without breakaway on old Windows).
void JoinKillOnCloseJob() {
  HANDLE job = ::CreateJobObjectW(nullptr, nullptr);
  if (job == nullptr) {
    return;
  }
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION info = {};
  info.BasicLimitInformation.LimitFlags =
      JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_BREAKAWAY_OK;
  if (!::SetInformationJobObject(job, JobObjectExtendedLimitInformation, &info,
                                 sizeof(info)) ||
      !::AssignProcessToJobObject(job, ::GetCurrentProcess())) {
    ::CloseHandle(job);
  }
  // On success the handle is deliberately kept open for the life of the process.
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // One OryvexVPN at a time: a second one would fight over the proxy ports.
  HANDLE single = ::CreateMutexW(nullptr, TRUE, L"Local\\OryvexVPN.SingleInstance");
  if (single != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"OryvexVPN");
    if (existing != nullptr) {
      ::ShowWindow(existing, SW_RESTORE);
      ::SetForegroundWindow(existing);
    }
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  JoinKillOnCloseJob();

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments = GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(80, 40);
  Win32Window::Size size(480, 860);
  if (!window.Create(L"OryvexVPN", origin, size)) {
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

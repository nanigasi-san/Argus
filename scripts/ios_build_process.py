"""Forward build logs and begin Simulator startup after Xcode preparation."""
import subprocess


def build_app(command, on_compilation=None):
    if on_compilation is None:
        subprocess.run(command, check=True)
        return
    # Flutter/Xcode resolve packages and inspect SDKs before the build
    # description. A cold Simulator boot delayed these probes in CI.
    triggered = False
    pending = ""
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          text=True, bufsize=1) as process:
        while character := process.stdout.read(1):
            pending += character
            if not triggered and "Build description signature:" in pending:
                print(pending, end="", flush=True)
                pending = ""
                on_compilation()
                triggered = True
            elif character == "\n":
                print(pending, end="", flush=True)
                pending = ""
        print(pending, end="", flush=True)
        status = process.wait()
    if status != 0:
        raise subprocess.CalledProcessError(status, command)
    if not triggered:
        # Future log formats may lose the overlap, but never bypass readiness.
        on_compilation()

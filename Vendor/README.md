# Bundled metadata dependency

TagLib 2.2.1, unmodified source, is compiled statically into Still Music.
Source: https://taglib.org/releases/taglib-2.2.1.tar.gz
SHA-256: 7e76b5299dcef427c486bffe455098470c8da91cf3ccb9ea804893df57389b5e

TagLib is used under its Mozilla Public License 1.1 option; see
`taglib-2.2.1/COPYING.MPL`. Its bundled utfcpp headers use the Boost Software
License 1.0, included in `taglib-2.2.1/3rdparty/utfcpp/LICENSE`.
The complete corresponding dependency sources are included in this repository
and available at the source URL above. They remain separate from Still's code.

Build with `bash scripts/build-taglib.sh` (requires CMake and Apple C++ tools).
The app build script calls this automatically. No Homebrew libraries or helper
executables are required on the listener's Mac.

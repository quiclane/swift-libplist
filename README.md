# swift-libplist

[libplist](https://github.com/libimobiledevice/libplist) **2.7.0**, repackaged as a
binary **Swift Package** for **macOS and iOS**. Drop the repo URL into Xcode and you get
the full libplist C API (and the optional C++ wrapper) as a prebuilt, multi-architecture
`XCFramework` — no autotools, no build step, no `main` symbol to collide with your app.

```
https://github.com/quiclane/swift-libplist
```

## Install (Xcode)

1. **File ▸ Add Package Dependencies…**
2. Paste the URL above.
3. Dependency rule: **Up to Next Major Version** from `2.7.1` (or pin **Exact** `2.7.1`).
4. Add the **`plist`** library product to your app target.

### Or in `Package.swift`

```swift
dependencies: [
    .package(url: "https://github.com/quiclane/swift-libplist.git", from: "2.7.1")
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "plist", package: "swift-libplist")
    ])
]
```

## Usage

```swift
import plist

let dict = plist_new_dict()
plist_dict_set_item(dict, "answer", plist_new_uint(42))

var xml: UnsafeMutablePointer<CChar>? = nil
var len: UInt32 = 0
plist_to_xml(dict, &xml, &len)
print(String(cString: xml!))
plist_free(dict)
```

From C / Objective-C(++) the headers resolve with angle brackets:

```c
#include <plist/plist.h>
```

> The C++ wrapper (`#include <plist/plist++.h>`) is also compiled into the archives.
> It is only linked in if you actually reference it; a target that touches the C++ API
> must link the C++ standard library (`-lc++`), which Xcode adds automatically for any
> target containing C++/Objective-C++ sources.

## What's in this repo

| Path | Description |
|------|-------------|
| `plist.xcframework/` | Binary framework used by SwiftPM (macOS + iOS device + iOS simulator slices). |
| `libplist-macos.a` | macOS static library (`arm64` + `x86_64`). |
| `libplist-ios.a` | iOS **device** static library (`arm64`). |
| `libplist-ios-sim.a` | iOS **simulator** static library (`arm64` + `x86_64`). |
| `include/plist/*.h` | Public headers — add `-Iinclude` and `#include <plist/plist.h>` for manual/non-SwiftPM use. |
| `include/module.modulemap` | Clang module map for the static libs. |
| `scripts/build-xcframework.sh` | Reproducible build (clones libplist `2.7.0`, configures, compiles). |
| `COPYING`, `COPYING.LESSER` | Upstream license texts. |

Each `.a` is a combined archive containing the C library (`libplist-2.0` + `libcnary`)
and the C++ wrapper (`libplist++-2.0`). The command-line tools (`plistutil`) are **not**
built, so the archives export **no `main` symbol**.

| Slice | Architectures | Min deployment |
|-------|---------------|----------------|
| macOS | `arm64`, `x86_64` | macOS 11.0 |
| iOS device | `arm64` | iOS 13.0 |
| iOS simulator | `arm64`, `x86_64` | iOS 13.0 |

## Rebuilding / bumping the libplist version

```sh
LIBPLIST_TAG=2.7.0 MIN_IOS=13.0 MIN_MAC=11.0 scripts/build-xcframework.sh
```

Requires Xcode, autoconf/automake/libtool, and pkg-config (`brew install autoconf automake libtool pkg-config`).
The script clones the pinned upstream tag, runs `./configure` once to generate `config.h`
(its values are identical across Apple/Darwin platforms), then compiles every slice with
`clang` and assembles the `XCFramework`.

## Versioning

Tags are **immutable** — once published they are never moved or deleted. The
`major.minor` of a tag mirrors the upstream libplist release it wraps; the `patch`
component is the packaging revision. Pin to an exact tag for fully reproducible builds.

| Tag | libplist | Platforms |
|-----|----------|-----------|
| `2.7.0` | 2.7.0 | iOS only |
| `2.7.1` | 2.7.0 | macOS + iOS |

## License

libplist is licensed under the **GNU Lesser General Public License v2.1 or later**
(see [`COPYING.LESSER`](COPYING.LESSER) / [`COPYING`](COPYING)). This repository only
repackages the upstream sources and binaries; all copyright remains with the
[libimobiledevice project](https://github.com/libimobiledevice/libplist) and its authors.

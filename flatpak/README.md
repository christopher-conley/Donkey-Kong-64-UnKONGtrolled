Before building the Flatpak, you must build the patches on the root directory first. **The LLVM Extension for freedesktop does not include the MIPS compiler and will fail to build the patches inside the flatpak**.
```sh
make -C patches CC=clang LD=ld.lld
```

Build
```sh
flatpak-builder --force-clean --user --install-deps-from=flathub --repo=repo --install builddir io.github.dk64unkongtrolled.dk64unkongtrolled.json
```

Bundle
```sh
flatpak build-bundle repo io.github.dk64unkongtrolled.dk64unkongtrolled.flatpak io.github.dk64unkongtrolled.dk64unkongtrolled --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo
```


# Chess

<b align="center">3D Chess in Zig using SDL3 + OpenGL</b>

<br>

Work-in-progress chess program.

<p align="center">
    <img src="https://github.com/user-attachments/assets/994a00d8-7f07-44a8-86a2-5e7ac609e869" width=300 height=300 alt="Preview Image" />
</p>

Current To-Do:
- Check and resolving check
- Pawn promotion
- FEN loading
- Subtle movement animations for the pieces
- En passant

## Installing
Should work fine on Linux as long as you have SDL3 and OpenGL installed.

- NixOS
    - `nix develop`
    - `zig build run`

- Windows
    - Download SDL3-devel (e.g. from https://github.com/libsdl-org/SDL/releases) and unpack it
    - Create `lib` folder
    - Copy the SDL3's `include` folder, `libSDL3.dll.a`, and `SDL3.dll` into the `lib` folder of this project
    - `zig build run`

<br>

Meshes taken from [OpenGameArt](https://opengameart.org/content/rough-chess-piece)

# Film colour tables

`film_tables.bin.gz` holds 26 colour tables (3D LUTs) for the Image
element's "Colour table" adjustment, each resampled to 25 points a side
from a HaldCLUT in the collection at https://github.com/NatronGitHub/clut.

They are licensed under the Creative Commons Attribution-ShareAlike 4.0
International licence (https://creativecommons.org/licenses/by-sa/4.0/),
as the originals are, and are by:

- Pat David (black and white, colour slide, colour negative, instant):
  http://blog.patdavid.net/2013/08/film-emulation-presets-in-gmic-gimp.html
- Juan Melara (print films):
  http://juanmelara.com.au/print-film-emulation-luts-for-download
- Marc Roovers (PictureFX):
  http://www.digicrea.be/haldclut-set-style-a-la-nik-software/

Changes: resampled from 64 to 25 points a side, 8 bits a channel, and
renamed by look rather than by the film each approximates. They are an
approximation of a look; no film maker made or endorses them.

## Format

gzip of: `BRLUT2`, a little-endian u16 count, then for each table a u8
name length, the name (UTF-8), a u8 size n, and n³ × 3 bytes: the red,
green and blue planes in turn, each n³ values with red changing fastest,
blue slowest, stored as the difference from the value before along red
(the first of each row as itself), modulo 256.

| Name | From |
|---|---|
| bw-press | bw/kodak_tri-x_400 |
| bw-fast | bw/ilford_delta_3200 |
| bw-fine | bw/agfa_apx_25 |
| bw-infrared | bw/kodak_hie_(hs_infra) |
| bw-instant | bw/polaroid_667 |
| bw-ortho | bw/rollei_ortho_25 |
| slide-vivid | colorslide/fuji_velvia_50 |
| slide-warm | colorslide/kodak_kodachrome_64 |
| slide-soft | colorslide/fuji_astia_100f |
| slide-saturated | colorslide/kodak_ektachrome_100_vs |
| cross-process | colorslide/lomography_x-pro_slide_200 |
| instant-slide | colorslide/polaroid_polachrome |
| portrait-warm | negative_new/kodak_portra_400 |
| portrait-cool | negative_new/fuji_400h |
| portrait-fast | negative_new/fuji_800z |
| everyday | negative_color/fuji_superia_200 |
| everyday-punchy | negative_color/agfa_vista_200 |
| redscale | negative_color/lomography_redscale_100 |
| night | negative_old/fuji_superia_1600 |
| cinema-warm | print/kodak2383_constlmap |
| cinema-cool | print/fuji3513_constlmap |
| sepia | picturefx/analogfx_sepia_color |
| summer-heat | picturefx/goldfx_summer_heat |
| antique | picturefx/analogfx_anno_1870_color |
| instant-warm | instant_consumer/polaroid_px-70_warm |
| instant-cold | instant_consumer/polaroid_px-100uv+_cold |

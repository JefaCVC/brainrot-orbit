// BRAINROT ORBIT — make.fun roblox-brainrot-01 entrypoint (Node 22, standard library only).
//
// What this program does: it hands the game in. It takes the Rojo-built place
// (game.rbxl), the Luau sources (src/), the Studio screenshots (screenshots/)
// and the published play link (PLAY.json) from beside this file, copies them
// into the output directory, and writes dossier.json — the summary the judge
// reads — with the kit's vendored library.
//
// Build the place first:  rojo build default.project.json --output game.rbxl
// Run it locally like this: mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts
//
// The grader refuses any output name that does not start with a letter, a
// digit or _ (or that holds anything but letters, digits, . _ and -), so the
// directory copies below skip every dot-file and dot-directory at any depth
// (.gitkeep, .DS_Store, .git, ...). Nothing else is filtered.

import { copyFileSync, cpSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildDossier } from './vendor/makefun-roblox.ts';

// The repository root (this file's directory) and the hand-in directory.
// Inside the grader MAKEFUN_OUTPUT_DIR is unset and the output is /output.
const repoRoot = fileURLToPath(new URL('.', import.meta.url));
const outputDir = process.env.MAKEFUN_OUTPUT_DIR ?? '/output';

// cpSync filter: keep a path only when its own name does not start with a dot.
function isNotDotfile(path: string): boolean {
  return !basename(path).startsWith('.');
}

// The place file and the play link go over as single files.
copyFileSync(join(repoRoot, 'game.rbxl'), join(outputDir, 'game.rbxl'));
copyFileSync(join(repoRoot, 'PLAY.json'), join(outputDir, 'PLAY.json'));

// Sources and screenshots go over as whole trees, dot-files left behind.
cpSync(join(repoRoot, 'src'), join(outputDir, 'src'), { recursive: true, filter: isNotDotfile });
mkdirSync(join(outputDir, 'screenshots'), { recursive: true });
if (existsSync(join(repoRoot, 'screenshots'))) {
  cpSync(join(repoRoot, 'screenshots'), join(outputDir, 'screenshots'), {
    recursive: true,
    filter: isNotDotfile,
  });
}

// The dossier: the gate's own caps, so a build this program accepts is one
// the scorer accepts too (text capped at 64 KiB; at most 4 screenshots of at
// most 256 KiB each; at most 500,000 place instances; scripts' sources at
// most 8 MiB in all; scripts' instance paths at most 1,048,576 chars).
const dossier = buildDossier(outputDir, {
  text_max_bytes: 65536,
  screenshots: { max: 4, max_bytes: 262144 },
  max_instances: 500000,
  scripts_max_source_bytes: 8388608,
  scripts_max_path_chars: 1048576,
});
writeFileSync(join(outputDir, 'dossier.json'), dossier);

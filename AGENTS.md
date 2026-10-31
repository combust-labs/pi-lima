# AGENTS.md

Notes from iterating on the GPU blog post (`docs/2026-10-29-gpu-in-a-vm-on-apple-silicon.md`). The goal of this file is to capture what I learned about the author's writing style so future blog posts in this repo don't repeat the same mistakes.

The author iterates on drafts in their own voice. Treat the patterns below as observed behaviour, not as a rigid house style — when in doubt, ask.

## What this file is not

This is not the author's personal house style. It is what I learned about *this particular blog post*, by diffing the LLM-assisted first draft against the author's hand-edits. Some patterns are probably author-wide; some may be post-specific. I have not always been able to tell the two apart, and where I could not, I have said so.

## Section headings

- The author removed the `§` symbol from in-body section headings. Final form is plain lowercase: `## background`, `## the symptom`, `## the fix`. I had matched this off the reference articles on gruchalski.com, where `§` does appear. I do not know whether the author considers `§` a TOC-only convention, or whether it is post-specific.
- Headings stay short, generally one or two words, sometimes a noun phrase (`the root cause`, `the comment that pointed the way`). No emdashes in headings.
- Section titles can be informal and colloquial. The opening/setup section in this post is titled `## give 'em all` — a casual imperative that I cannot fully decode. I do not know whether this is post-specific or whether the author uses colloquial section titles elsewhere. When in doubt, mirror the tone of the post's first body section rather than reach for a neutral title.

## Front matter

- `author: radek gruchalski` was changed to `author: radek gruchalski (coauthor)`. There is a coauthor blockquote at the top of the body disclosing that the post was written by an LLM under the author's guidance. This is consistent with the way this post was produced. I do not know whether the author marks all LLM-assisted posts this way or whether it is post-specific.
- The author noted "emdash: any remaining, remain on purpose. Some did not survive, and some have been added." Read literally, the policy is *intentional emdashes only*. I had been sprinkling emdashes as a stylistic tic; the author kept the ones that earned their place and dropped the rest. I do not have a hard rule for "when does an emdash earn its place" beyond this.

## Opening

- The author replaced my "Why bother." rhetorical lead with a longer philosophical setup about what an autonomous agent needs: freedom to navigate in the real world, browser applications, Kubernetes operators, "trip over the hurdles on its own, like we do." I had been too quick to get to the technical premise. The author opens by establishing *why this matters to the agent*, not *why this is interesting to me*.
- A second new sentence — "Not even Docker supports GPU in containers on macOS!" — sharpens the "this is the tough part" framing with a specific, slightly dismissive aside. The author is willing to take a side and be a bit punchy in the opening.
- The author also added provenance about how the investigation started: "The place where I have seen the mention of a Linux VM on macOS + the GPU was in Colima, the `colima model` command." This is a small personal detail that grounds the post. Worth keeping in mind: where did *I* first encounter the problem? The reader benefits from knowing.

## Voice and tone — what I got wrong

- **Less editorialising.** I had closed the comment-that-pointed-the-way section with a 3-sentence reflection on how good bug reports work. The author replaced it with one sentence: "This single sentence changes everything." I had closed §the root cause with "It is correct. It is the answer." The author dropped both sentences and left "Not much to add to that analysis." The author lets the facts do the work; I had been writing *about* the facts.
- **Shorter closings.** I had lifted the closing line "I'll write some more soon." from the author's earlier articles. The author removed it. I do not know if this closing line is wrong for the author in general, or wrong for this particular post. I would not reach for it again without checking.
- **Tighter recipe.** The §recipe section lost its closing line ("Replace any one of those dependencies and the GPU stops enumerating") and one of its three dependency bullets (the kernel-parameter-not-yet-advertised one). The author replaced the bullet list with a single operational recommendation: "it's probably wise to hold forks of all dependencies." Shorter, more actionable, less rhetorical.

## Voice and tone — what seemed to land

- **Definitions as standalone sentences.** The author split the `VK_DRIVER_FILES` definition out of a long compound sentence into its own sentence, then defined "ICDs" in its own sentence after that. The pattern is: name the thing, then define it, then use it. I had defined multiple things inside one parenthetical, which is denser but harder to follow.
- **Concrete specifics.** The author added "Apple M5 Pro" instead of "Apple Mx Pro", added "WebGPU" to the list of GPU runtimes, added "Firecracker microVM" as a real example of what nested virt enables. Specifics anchor the post in something the reader can verify or look up. I had been generic on purpose and the author kept pushing toward specifics.
- **Empirically grounded claims.** Where the author updated a fact ("HWE kernel is now 7.0, not 6.x"), they did so with a versioned citation ("At the time of writing it is `24.04.5 LTS (HWE)` with kernel version `7.0`"). When the author was uncertain about something ("Installing an edge kernel could be an option"), they signalled it. The author does not over-claim.
- **The author added a concrete next step.** Where I had ended the upstream-solution section with a reflection, the author added a one-line `apt-get install` command. If the post raises a problem, the post also raises an actionable next step.
- **"Whitespace is critical."** A standalone sentence after the diff blocks. The author is comfortable with very short standalone sentences that drive a single point home. I had been padding for flow.
- **Section ordering — practical before future-looking.** The final section order is `give 'em all` → `background` → `the symptom` → `issue #102` → `the comment that pointed the way` → `the root cause` → `the fix` → `what this enables` → `build mesa` → `the recipe, in summary` → `the upstream solution` → `closing words`. Notably, `the recipe, in summary` comes **before** `the upstream solution` (it did not in my draft — I had put the upstream solution first). The author wants the reader to walk away with the working recipe before they read about the future-looking upstream fix. I had framed the upstream solution as the hopeful ending; the author reframed it as the footnote.

## Diff inclusion

- The full Mesa patch diffs for both 22.3.6 and 25.0.7 versions are now included inline in §the fix, as `diff` code blocks. I had described the patch in prose only. The author's call: show the patch, because it is short and is the entire point of the section. If a blog post is going to make a specific technical argument about a patch, the patch should be in the post.

## Self-contained posts — show the commands

- The post now contains a `## build mesa` section with concrete shell commands: `apt-get install` for build tools, `git clone`, `git checkout`, `git apply`, `meson setup`, `meson compile`, `meson install`, plus the `VK_DRIVER_FILES` export. I had described the build in prose only and pointed the reader at `pi-builder.yaml` for the actual commands. The author added the commands inline. The pattern: **if the post argues for a specific implementation, include the actual implementation in the post.** A reader should be able to follow the article end to end without cross-referencing another file in the repo.
- The placement matters. `## build mesa` sits between `## what this enables` and `## the recipe, in summary` — the practical "do this" content is sandwiched between the conceptual explanation and the high-level summary. This reinforces the "practical before future-looking" ordering noted above.
- The build section closes with a short declarative line: *"Now `vulkaninfo --summary` simply works."* The author is comfortable with understated triumph at the end of a setup section. I would not have written that line; the author did.
- The patch path inside the build commands is left as `/path/to/the/mesa-$MESA_VERSION.krunkit-16k.patch` — a placeholder. The author did not hardcode a path because the blog post is not tied to a specific checkout of pi-lima. **When showing commands in a post, use placeholders for paths that depend on where the reader got the patch, the config, the source, etc.**

## Hugo conventions

The post uses Hugo-specific syntax in two places:

- `{{<toc>}}` shortcode at the top of the body to auto-generate a table of contents from the headings. This replaced the manual "I will cover" list I had drafted. If the post has more than a handful of sections, prefer `{{<toc>}}` over maintaining a manual list.
- `[^N]` footnotes for references, with `[^N]: URL` definitions at the bottom of the file. This replaced the inline `[N]: URL` Markdown reference style. Hugo renders these as proper footnotes at the bottom of the page. **Use Hugo footnotes for citations, not inline Markdown reference links.**

I do not know whether `{{<toc>}}` and `[^N]` are author-wide conventions for Hugo posts in this repo or only for this post.

## File paths and disk-state references

- The author updated several references to the current disk state:
  - `bin/image/resources/wtf-mesa.tar.gz` → references to the `pi-lima.bootstrap` directory tree.
  - `pinned in pi-builder.yaml` → "reside in the _pi-lima.bootstrap_ directory".
- When a blog post refers to specific files, the file paths have to match what is actually on disk. I had inherited stale paths from earlier drafts and the author caught them. **Before publishing a post, walk every filesystem reference and verify it against the current state of the repo.**

## Term glosses — keep them, but not on every term

- I had added a parenthetical gloss for almost every technical term on first mention, on the explicit instruction "Don't assume that the reader is fluent in the subject." The author kept most of those glosses but shortened some of the more elaborate ones (e.g. the `O(n)` of "ioctl — a syscall for sending a command to a device driver" became "ioctl, an ioctl being a syscall for sending a command to a device driver"). The em-dash was dropped, but the gloss stayed. The policy is *gloss technical terms*, not *sprinkle parentheticals*. An unnecessary gloss is worse than a missing one.
- The author did keep every gloss on a term that could plausibly be unknown to a non-specialist. Do not strip glosses from "ICD", "ioctl", "VK_DRIVER_FILES", "PAGE_ALIGN", etc. — they are doing real work for the reader.

## Things I genuinely do not know

- Whether the `(coauthor)` attribution is post-specific or a permanent policy for LLM-assisted drafts.
- Whether `I'll write some more soon.` is wrong for this author in general or just for this post.
- Whether the `§`-symbol removal is post-specific or a wider convention.
- The exact rule for when an emdash earns its place. The coauthor blockquote says they are intentional, not arbitrary.
- Whether "Apple M5 Pro" reflects the author's actual hardware or was just a concrete placeholder chosen over the generic "Mx Pro".
- The current Ubuntu HWE kernel version (the author says 7.0; I have not verified).

I have flagged these as unknown rather than guessed, because the user asked for honesty over invention.

## Default checklist for future blog posts in this repo

1. Walk every filesystem reference in the post against the current repo state. Fix any stale paths.
2. Section headings: plain lowercase, no `§`, no emdash, one short noun phrase. The opening/setup section may have a colloquial title — match the tone of the post's first body section.
3. Open with why-it-matters-to-the-agent, not why-it-is-interesting-to-me. Include a concrete personal detail that grounds the investigation.
4. Define each technical term on first use, in its own sentence or short appositive, not buried inside a longer compound sentence. Do not over-gloss.
5. Do not write reflections *about* facts. Let the facts do the work.
6. Show the actual code, patch, command, or config being argued for, in a code block, if it fits in the post. Include the commands inline so the post is self-contained — the reader should not need to cross-reference another file.
7. Order sections so practical content comes before future-looking content: build steps / recipe / summary before upstream-fix / future-work sections.
8. Use `{{<toc>}}` for tables of contents (Hugo), and `[^N]` footnotes for citations rather than inline Markdown reference links.
9. Use placeholders for paths that depend on where the reader got the file (`/path/to/the/patch`), rather than hardcoding paths tied to a specific repo checkout.
10. End with an actionable next step where possible, not a reflection.
11. Do not reach for stock closings like "I'll write some more soon." without checking that the author uses them.
12. Emdashes are intentional. Use sparingly, keep only the ones that earn their place.
13. Front matter: `author: radek gruchalski (coauthor)` if the post was LLM-assisted, otherwise `author: radek gruchalski`. Add a coauthor blockquote at the top of the body disclosing the LLM authorship and noting any deliberate stylistic exceptions (like the emdash policy).

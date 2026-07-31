# NiceLookingTerminal Manual UI Smoke-Test Checklist

Run this checklist on the built macOS app after UI or terminal changes. Record the date, macOS version, commit, and pass/fail result before starting. Use a disposable fixture directory and a disposable image; do not use real secrets or production project files.

## Setup

- [ ] Run `swift build`, `swift test`, and `./build_app.sh`, then launch `dist/NiceLookingTerminal.app`.
- [ ] Confirm the first terminal opens in `~/Desktop/Projects` when it exists, otherwise `~/Projects` or the home directory fallback.
- [ ] Create a temporary fixture project containing a file named `smoke test.txt` and a small screenshot.

## Terminal launch and workspace behavior

- [ ] **Shell launch:** Type `pwd`, `printf 'shell-ok\\n'`, and `exit` only if testing in a disposable tab. The shell is interactive, accepts input, and renders the command output.
- [ ] **Project launch:** Open the fixture directory from the Workspace sidebar. A new terminal opens there and uses the directory name as its title.
- [ ] **Multiple sessions:** Create two or more tabs. Click an inactive cell and confirm it becomes active; maximize and restore a cell.
- [ ] **Large grid:** Restore or create thirty tabs. Use the grid scrollbar/gutters to reach every pane and confirm no pane is compressed below its readable minimum.
- [ ] **Streaming scroll:** Run a continuously producing command, scroll upward, and confirm new output does not move the viewport. Confirm **New output** appears and returns to the latest line.
- [ ] **Large history:** Produce 100,000 numbered lines and verify the first and last lines remain reachable.
- [ ] **Close and restore:** Close the active tab with its close control and with Cmd+W. Use Cmd+Shift+T to reopen the last closed tab, then relaunch the app and confirm saved sessions restore.
- [ ] **Process tree:** In a disposable tab, launch a background child process, close the pane, and confirm both the shell and child have exited.

## File and image input

- [ ] **Drag and drop:** Drag `smoke test.txt` into an active terminal. Confirm a path is inserted, the copied attachment exists under Application Support, and paths containing spaces remain one shell argument.
- [ ] **Clipboard image:** Copy the disposable screenshot, press Cmd+V in a terminal, and confirm a PNG path is inserted and the attachment can be read from the shell.
- [ ] **Input erase:** Type a disposable string, press Cmd+Backspace, and confirm the rendered input disappears without stale characters remaining.
- [ ] **ANSI repaint:** Display colored diff output, erase and replace the current input repeatedly, and confirm no stale colored rectangles or black bars remain.

## Planner

- [ ] **Whiteboard:** Switch to Planner → Whiteboard. Draw a pen stroke, rectangle, circle, and text. Select, drag, erase, change stroke/fill/font settings, and clear the board.
- [ ] **Kanban:** Switch to Planner → Kanban Board. Add a card with each priority, paste the disposable screenshot onto a card, move cards between columns, and delete a card.
- [ ] **Mode isolation:** Switch between Terminals and Planner and confirm terminal sessions remain available when returning to Terminals.

## Shortcuts and menus

- [ ] Cmd+T creates a terminal tab.
- [ ] Cmd+W closes the active terminal tab.
- [ ] Cmd+Shift+T restores the last closed tab or saved session set.
- [ ] Cmd+C, Cmd+V, Cmd+X, and Cmd+A continue to route to the focused terminal/text control.
- [ ] Cmd+Backspace clears the active terminal input line.
- [ ] Cmd+A selects all text in the focused native editor or terminal without clearing its contents.
- [ ] With onboarding, a terminal title editor, or Planner text editor focused, Cmd+W does not silently close a terminal behind that interface.
- [ ] The File and Edit menus expose the same actions and shortcuts as the keyboard handlers.

## Agent presets

- [ ] Cmd+O and **Open Codex** open the selected workspace in Codex Desktop; the local Codex terminal is clearly marked as not phone-synced.
- [ ] Open the agent preset menu and confirm the local Codex and AGY descriptors, icons, labels, and shortcuts are present.
- [ ] If the local machine is explicitly authorized and the corresponding CLI is installed, verify that selecting a preset creates a titled agent tab and inserts its configured command.
- [ ] Do not run real networked Codex or AGY sessions as part of automated testing. For a manual smoke run, stop after descriptor/tab/command verification unless an operator has explicitly authorized the session.

## Setup and storage

- [ ] First launch shows workspace, access profile, and phone-control setup on one screen.
- [ ] Full Agent Access remains selected after relaunch and effective access is rechecked for Workspace, Downloads, Documents, Desktop, and network.
- [ ] Setup cannot complete until its required tool, access, network, and Remote confirmation checks pass.
- [ ] **Open searchable transcript** opens persistent output; reveal, export, and confirmed delete actions work after relaunch.
- [ ] Runtime storage shows transcript and attachment sizes; cleanup removes only the described app-owned data.

## Packaging

- [ ] The local DMG contains NiceLookingTerminal and an Applications link and is clearly identified as local/ad-hoc.
- [ ] On a release machine, distribution mode produces a universal Developer ID–signed, notarized, stapled DMG that Gatekeeper accepts.
- [ ] Install and upgrade the release on a clean macOS account; confirm Full Disk Access is not requested again when bundle identity is unchanged.

## Result

- Commit tested: ____________________
- macOS version: ____________________
- Date: ____________________
- Result: PASS / FAIL
- Notes or reproduction details: __________________________________________

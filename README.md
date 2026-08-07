# Dock Management on macOS: From User Templates to Swift Tools

![Managed macOS Dock baseline](/dock-management/images/initial_login_dock_baseline seed.png)

For MacAdmins, the Dock has always been a deceptively small thing with a big operational footprint. It is the first place many users look for the tools they need, and it is one of the first places they notice when a Mac does not feel ready for work.

That is why Dock management keeps coming back in admin conversations. The goal usually sounds simple: remove the default clutter, add the core apps, maybe add Downloads or a web link, and let users get on with their day. The hard part is doing that without fighting the user, racing Setup Assistant, depending on an app that has not installed yet, or locking down a preference that should only have been a first-run suggestion.

## A Short History of Dock Management

![Dock management timeline](assets/dock-management/dock-management-timeline.svg)

Early Dock management often started with the Default User Template. Admins would build or edit a default account experience, then rely on macOS to copy those preferences into each new user account. For a while, this felt natural: image the Mac, shape the template, and let new users inherit the setup.

Over time, that approach became brittle. macOS changed, system protections increased, imaging gave way to enrollment workflows, and the timing of first login became more important than the contents of a template. Editing `/System/Library/User Template` also blurred an important line: was the Dock being set once for convenience, or was the admin trying to permanently manage it?

The next era leaned on scripts. Admins used `defaults`, `PlistBuddy`, AppleScript, shell scripts, and direct edits to `~/Library/Preferences/com.apple.dock.plist`. These approaches were flexible, but they also required a deep understanding of Dock plist structure, user context, preference caching, and when to restart or reload the Dock.

Configuration profiles and MDM payloads gave admins a supported way to enforce Dock settings. Profiles are still useful when the organization truly wants a managed Dock that users cannot freely change. But for many environments, especially schools, labs, and shared Macs, the desired behavior is softer: give users a helpful starting Dock, then leave them alone.

That gap is where tools such as `dockutil`, `docklib`, Outset workflows, Jamf policies, Munki payloads, and newer Swift-based tools became popular. Instead of treating the Dock as a static image artifact, admins could run a script at login, apply a known layout to the actual user account, and mark the work complete.

The modern pattern is less about "owning" the Dock forever and more about choosing the right moment to seed it.

## Common Dock Management Solutions

- **Default User Template edits**: Historical approach for seeding new accounts. Generally avoided today because it is fragile, hard to reason about across OS releases, and easy for Apple changes to invalidate.
- **Configuration profiles**: Best when the Dock must be enforced. Good for locked-down environments, but not ideal when users should be able to customize the Dock afterward.
- **MDM vendor Dock payloads**: Useful for simple, managed layouts. Flexibility varies by platform and payload implementation.
- **`defaults` and plist scripting**: Dependency-light and transparent, but requires careful handling of plist keys, app paths, user context, and Dock reload behavior.
- **`dockutil` scripts**: A long-standing community standard for adding, removing, moving, listing, and finding Dock items from scripts.
- **`docklib`**: A Python library approach used by some admins who prefer manipulating Dock data through a library rather than repeatedly shelling out to a command-line tool.
- **Outset login scripts**: Common pairing with Dock setup because it can run scripts at boot, login, login-once, login-every, or on demand.
- **Jamf, Munki, Mosyle, Intune, and other MDM orchestration**: Often used to install the tool, install apps first, then trigger the Dock script when the user session is ready.
- **Swift and native tools**: Increasingly attractive because modern macOS no longer includes Python 2, and Swift can better align with current Apple platform behavior.
- **User-facing selection tools**: Some admins are exploring SwiftDialog or similar interfaces so users or technicians can choose which app groups should appear in the Dock.

## The dockutil Story

[`dockutil`](https://github.com/kcrawford/dockutil) is one of the best-known tools in this space. The project describes itself as a command-line utility for managing macOS Dock items, and the current 3.x version is written in Swift.

The upstream README currently lists dockutil 3 compatibility for macOS Big Sur through Sonoma, with the 2.x series available for older macOS releases. For newer macOS releases, test before relying on it in production and watch the project issues, releases, and MacAdmins Slack discussions.

Its history mirrors the larger MacAdmin story. Earlier versions were Python-based and helped admins avoid hand-editing Dock plist structures. Version 1.x added important operational flags such as `--no-restart`, `--replacing`, `--remove all`, support for the Default User Template path, and `--version`.

Version 2.x continued to refine behavior across OS releases. It added support for multiple removals, removal by bundle identifier, spacer tiles, and logic to wait for Apple to finish setting up the Dock before modification, which is especially useful for first-login scripts.

Version 3.0.0 was the big transition: dockutil was rewritten in Swift for macOS 12.3 compatibility after Apple removed the system-provided Python 2 runtime. The Swift version kept feature compatibility with previous releases, added find/add/remove by bundle identifier, URL, or path, and allowed multiple add/remove actions in a single run. Later 3.1.x updates moved the project to Swift Package Manager and fixed sudo, Cryptex path, and macOS 14.4 Dock restart behavior.

That evolution matters because Dock management is not just a plist problem. It is also an OS lifecycle problem.

## What dockutil Can Do

The current dockutil README lists support for:

- Adding Dock items.
- Removing Dock items.
- Moving Dock items.
- Finding Dock items.
- Listing Dock items.
- Managing applications, folders, stacks, and URLs.
- Acting on the current user's Dock plist, a specific plist, a home directory, all home directories, or an alternate home-directory location.
- Positioning items by index, beginning, middle, end, before another item, after another item, or replacing another item.
- Choosing the apps or others Dock section.
- Setting folder stack display options such as view, display style, and sort order.
- Removing all items or spacer tiles.
- Adding spacer tiles.
- Suppressing Dock restart with `--no-restart` so a script can make multiple changes and restart the Dock once at the end.

These features make dockutil especially useful for repeatable first-login Dock setup. A typical pattern is:

1. Confirm the user session is real, not `root`, `loginwindow`, or Setup Assistant.
2. Confirm required apps are installed.
3. Remove unwanted default Dock items.
4. Add required apps and folders.
5. Use `--no-restart` on every command except the final change.
6. Restart or reload the Dock once.
7. Write a per-user receipt so the setup does not run again unless intended.

## Lessons From the #dock-management Community

The MacAdmins Slack `#dock-management` channel has years of practical troubleshooting around dockutil and related workflows. A few themes come up repeatedly.

- **Timing matters**. Running too early during enrollment or first login can lose the race against macOS creating or re-seeding the default Dock.
- **User context matters**. Many failures come from tools running as `root` and accidentally targeting `/var/root/Library/Preferences/com.apple.dock.plist` instead of the logged-in user's Dock.
- **Install order matters**. If an app is not installed yet, the Dock item may fail to add or may appear as a generic question-mark icon.
- **Profiles and scripts solve different problems**. Profiles are good for enforcement. Scripts are better for a one-time starting layout that users can later change.
- **Avoid unnecessary `--allhomes` use**. It can be useful for known local accounts, but it does not configure future accounts unless the workflow runs again, and broad recursive changes can surprise existing users.
- **Batch Dock changes when possible**. Repeatedly restarting the Dock creates flicker, delays, and inconsistent user experience. `--no-restart` is a small flag with a big payoff.
- **First-login workflows need receipts**. A "login every" trigger plus a per-user marker file can be more reliable than assuming a single enrollment-time policy happened at the perfect moment.
- **Paths change**. System apps moved from `/Applications` to `/System/Applications`, some Apple apps may live through Cryptex paths, and third-party app names can change during major updates.
- **New macOS releases need real testing**. Community reports around newer releases often involve changed Dock behavior, changed plist keys, or timing issues that older scripts did not anticipate.

The channel itself started in May 2016 with discussion focused on dockutil, and its topic now includes Dock items generally, including dockutil, docklib, and other Dock management tools.

## Repeating Community Requests

![Profile versus script decision guide](assets/dock-management/profile-vs-script-decision.svg)

If you spend time in MacAdmin Dock conversations, the same requests show up again and again. They are not repetitive because admins are missing something obvious. They are repetitive because Dock setup sits at the intersection of user identity, login timing, application installation, and Apple changing implementation details across macOS releases.

- **"How do I set the Dock once, then let users change it?"** Short answer: use a first-login or once-per-user script, write a per-user receipt, and do not enforce the Dock with a profile.
- **"Should I use a profile or a script?"** Short answer: use a profile when the Dock must stay managed; use a script when you only want to create the initial layout.
- **"Why did my script work in Terminal but fail from Jamf, Munki, ARD, or MDM?"** Short answer: check execution context. Terminal usually runs as the user, while management tools often run as `root`.
- **"How do I run this for the currently logged-in user?"** Short answer: detect the console user, get that user's UID, and run Dock commands in the GUI session with `launchctl asuser` or an equivalent method.
- **"Why did the Dock reset back to Apple's default layout?"** Short answer: the script probably ran too early, before macOS finished creating or re-seeding the first-login Dock.
- **"Why are there question marks in the Dock?"** Short answer: the item points to an app or file path that did not exist when it was added, or the app moved after an update.
- **"How do I add Downloads, Applications, network shares, or URLs?"** Short answer: treat folders, stacks, and URLs as first-class Dock items with labels, sections, view, display, sort, and position options.
- **"How do I avoid restarting the Dock over and over?"** Short answer: add `--no-restart` to intermediate dockutil actions, batch changes when possible, and restart the Dock once at the end.
- **"Can I apply this to every user?"** Short answer: yes, but use `--allhomes` deliberately. It affects existing homes and does not automatically configure users created later.
- **"How do I support multiple departments or roles?"** Short answer: keep Dock items in arrays, add optional sections, and use a small customization hook for department, lab, or account-specific logic.
- **"How do I know it actually worked?"** Short answer: run `dockutil --list`, verify expected items, log missing items, and write the run-once marker only after success.
- **"What changed in the latest macOS?"** Short answer: retest app paths, Dock plist behavior, Dock restart behavior, and first-login timing on every major macOS release.

## Frequent Dock Management Categories

Most Dock projects become easier to design when the request is sorted into a category first. The category decides whether you should use a profile, a script, a first-login workflow, a recurring repair workflow, or a user-choice interface.

- **Initial Dock seeding**: Set a clean starting Dock once for a new user, then allow the user to customize it. This is the most common fit for dockutil, Outset login-once scripts, Jamf once-per-user policies, and the Marriott Library template.
- **Enforced Dock management**: Keep the Dock in a fixed state and prevent or reverse user changes. This is a configuration profile or MDM payload problem, not just a dockutil problem.
- **Shared lab and classroom Docks**: Reset or seed Docks for machines used by many people. These workflows need a clear decision about whether the reset happens once per user, every login, or after a reimage/redeployment.
- **Student baseline Docks**: Provide only the essentials: browser, learning platform or library link, self-service app, and Downloads. The goal is usually a limited first-run Dock, not a permanently locked Dock.
- **Staff baseline Docks**: Provide work essentials: browser, productivity apps, self-service, support/ticket link, communications apps, and Downloads. Staff setups often need optional items based on department or role.
- **Technician or admin Docks**: Add tools such as Terminal, Activity Monitor, management portals, support utilities, or local admin resources only for technician accounts.
- **Application lifecycle repair**: Fix Dock items after app moves, renames, major upgrades, or vendor changes. Examples include Office, Adobe, system app moves, and apps that change paths between releases.
- **First-login timing and enrollment workflows**: Handle the fragile window after Setup Assistant, ADE, Jamf Connect, account creation, or MDM enrollment. These workflows need waits, retries, and a real logged-in user.
- **User-context correction**: Make scripts target the active GUI user instead of `root`. This category covers console-user detection, UID lookup, `launchctl asuser`, home-directory targeting, and plist targeting.
- **Existing-user cleanup**: Remove legacy items, stale paths, question-mark icons, old app names, or unwanted defaults without completely rebuilding a user's Dock.
- **Folder, stack, and URL management**: Add Downloads, Applications, network shares, documentation links, support links, or internal portals with the right Dock section, view, display, sort, and label.
- **Multi-role customization**: Use arrays, role detection, smart groups, departments, labs, or local account names to build different Docks from one reusable script.
- **All-homes or specific-home management**: Apply a change to known local homes, a specific home directory, or a specific Dock plist. This is useful for migrations and repairs, but should be used carefully because it can affect existing users.
- **Verification and reporting**: List the Dock after changes, confirm expected items are present, log missing apps, and write a marker or receipt. This is especially important when Dock setup runs during zero-touch deployment.
- **Modern macOS compatibility**: Track changes in app paths, Cryptex locations, Python removal, Dock plist behavior, Dock restart behavior, and new OS release timing issues.
- **User-choice Dock personalization**: Let users, help desk staff, or technicians choose a Dock layout from a small interface, then apply the selected apps and links with dockutil or another backend.

These categories also help with documentation. Instead of saying "we manage the Dock," say whether you seed it, enforce it, repair it, personalize it, or reset it. That small distinction prevents a lot of policy and scripting confusion later.

## Practical Recommendations

For most modern deployments, the cleanest Dock strategy is:

- Use a configuration profile only when you mean to enforce the Dock.
- Use a script when you only want to seed an initial Dock.
- Run the script in the logged-in user's context or explicitly target that user's Dock plist.
- Wait until the Dock and Finder are running and the Dock plist exists.
- Verify app paths before adding them.
- Prefer bundle identifiers when supported and useful, but keep path validation because real app locations still matter.
- Use `--no-restart` for intermediate changes.
- Restart the Dock once after all changes are written.
- Leave a per-user receipt so the Dock is not reset every login.
- Test on the macOS versions you actually support, especially after major macOS updates.

For shared labs, carts, loaner devices, and student Macs, consider whether the Dock should be rebuilt every login, once per user, or once per device. Those are different policies, and the script should make that decision obvious.

## A Generic Dock Setup Pattern

Here is a human-readable structure that tends to age well:

```text
define required apps
define optional apps
define folders and URLs
find logged-in user
skip if no real user session exists
skip if the per-user receipt already exists
wait for Dock, Finder, and Dock plist
confirm dockutil is installed and executable
remove unwanted Dock items
add required items that exist
add optional items only if present
add Downloads or other folders
restart Dock once
write receipt
log what changed
```

That structure is intentionally boring. Boring is good here. Dock setup should be predictable, readable, and easy for the next admin to customize.

## Example: Marriott Library Initial Login Template

The Marriott Library script at [`dock_setup_student_template.sh`](dock_setup_student_template.sh) is a good example of turning those recurring community lessons into a reusable template.

It is designed for an initial-login setup where student and staff Macs receive a limited, useful Dock baseline without permanently enforcing the user's Dock. The defaults are intentionally conservative:

- It targets the active GUI user with `DOCK_TARGET_MODE="current_user"`.
- It runs dockutil through the user's GUI session with `launchctl asuser`.
- It sets `RUN_ONCE_PER_USER=true` so the Dock is seeded once per user.
- It uses a marker file in the user's preferences folder to avoid rebuilding the Dock every login.
- It clears the default Dock first with `CLEAR_DOCK_FIRST=true`.
- It validates configured app and folder paths before adding them.
- It skips missing optional items unless `REQUIRE_ALL_ITEMS=true`.
- It waits for Dock, Finder, and a stable Dock plist before making changes.
- It builds a single dockutil 3 action batch using `--no-restart`.
- On the normal path, it restarts the Dock once at the end for current-user workflows.
- It verifies the resulting Dock contents and retries once if verification fails.

For a student/staff limited Dock, the main customization area is the site configuration block:

```bash
readonly ORG_NAME="Example Organization"
readonly DOCK_TARGET_MODE="current_user"
readonly RUN_ONCE_PER_USER=true
readonly CLEAR_DOCK_FIRST=true
readonly REQUIRE_ALL_ITEMS=false
```

Then the Dock content is managed through arrays:

```bash
declare -a REMOVE_ITEMS_FROM_DOCK=(
    "all"
)

declare -a ADD_APPS_TO_DOCK=(
    "/Applications/Google Chrome.app"
    "/Applications/Firefox.app"
    "/System/Applications/Safari.app"
    "/System/Applications/System Settings.app"
)

declare -a ADD_FOLDERS_TO_DOCK=(
    "\$HOME/Downloads"
)

declare -a ADD_WEBLOCATIONS_TO_DOCK=(
    "https://support.example.org|Support"
)
```

That makes the script easy for other MacAdmins to adopt: replace the organization label, adjust the app list, add or remove folders and web links, and deploy it with the local login workflow of choice.

For a library, school, or lab environment, a practical split might look like this:

- **Student baseline**: browser, library/self-service portal, learning platform link, Downloads stack.
- **Staff baseline**: browser, productivity apps, self-service portal, ticket/support link, Downloads stack.
- **Technician baseline**: optional admin utilities added through the `customize_dock_items_for_user` hook for a known local technician account.
- **Shared device baseline**: rebuild once per user if users keep accounts, or every login only if the device model requires a reset experience.

The most important choice is whether the Dock should be limited once or limited forever. This script is best suited to "limited once." If the requirement is "users may never change this Dock," use a configuration profile instead.

### How the Script Handles Timing

![First-login Dock setup timing flow](assets/dock-management/first-login-timing-flow.svg)

The Marriott Library template treats timing as a first-class problem instead of adding one large `sleep` and hoping for the best. That matters because Dock setup often runs during the noisy part of first login, when the user account exists but macOS may still be building preferences, launching Finder, starting the Dock, or applying default Dock items.

The script uses several small timing gates:

- **Valid user wait**: It waits up to `USER_WAIT_TIMEOUT=180` seconds for a real console user and skips system states such as `root`, `_mbsetupuser`, and `loginwindow`.
- **Short polling interval**: It uses `PROCESS_CHECK_INTERVAL=1` second to keep checks responsive without relying on fractional shell arithmetic.
- **Dock and Finder readiness**: For current-user workflows, it waits until both `Dock` and `Finder` are running before touching the Dock plist.
- **Process timeout**: It uses `PROCESS_WAIT_TIMEOUT=30` seconds while waiting for required processes, then fails clearly if the GUI session never becomes ready.
- **Dock plist creation wait**: It checks for `~/Library/Preferences/com.apple.dock.plist` before making changes.
- **Dock plist readability check**: It verifies the plist can be read with `plutil` or `defaults` before trusting it.
- **Default Dock setup check**: If the Dock appears empty, it waits briefly because Apple may still be creating the initial default Dock.
- **Stability hash check**: It hashes the current Dock preferences and waits until the hash remains stable for the configured stable check count.
- **Graceful timeout behavior**: If Dock stabilization does not happen within the short `dock_timeout=15` second window, it logs a warning and exits without changing the user's Dock. This preserves the macOS default Dock rather than applying changes during an unstable first-login state.
- **Batched dockutil changes**: It builds one dockutil 3 action batch and adds `--no-restart` to each add/remove action, avoiding repeated Dock restarts during setup.
- **Verification retry**: After setup, it lists and verifies the Dock contents. If verification fails, it runs one quick setup retry and verifies again.
- **Controlled Dock restart**: On the normal path, it waits `DOCK_RESTART_DELAY=1` second, restarts the Dock once, retries that restart up to three times if needed, then waits up to 15 seconds for the Dock process to return. If verification fails and the quick retry path runs, that retry can also restart the Dock before the final restart handling.
- **Completion marker after success**: It writes the run-once marker only after setup and restart handling complete, so a failed or skipped first run does not incorrectly mark the user as done.

In practice, this makes the script behave like a cautious first-login worker: wait for the right user, wait for the Dock to exist, wait for the Dock to stop changing, make the changes in one pass, verify the result, restart the Dock in a controlled way, and only then write the receipt.

### How the Script Answers Community Questions

The Marriott Library template is useful because it turns recurring `#dock-management` advice into explicit script behavior. It does not just say "run dockutil at login"; it defines the user context, timing checks, validation, batching, verification, and run-once behavior that make that advice reliable.

- **Set the Dock once, then let users change it**: `RUN_ONCE_PER_USER=true` and the per-user marker file seed the Dock once without enforcing it forever.
- **Profile or script**: The script is for initial setup. If the Dock must remain locked, a configuration profile is still the better fit.
- **Terminal works, MDM fails**: The script targets the active GUI user and runs dockutil with `launchctl asuser`, avoiding the common root-context Dock plist problem.
- **First-login timing**: The script waits for a real user, Dock, Finder, Dock plist creation, plist readability, and Dock preference stability before making changes.
- **Dock resets to Apple defaults**: If the Dock is not stable within the configured timeout, the script exits instead of racing macOS during first-login setup.
- **Question-mark icons**: The script validates app and folder paths before adding items and skips missing optional items unless `REQUIRE_ALL_ITEMS=true`.
- **Folders, stacks, and URLs**: The arrays support apps, folders, web locations, labels, sections, views, display styles, sorting, positions, and spacers.
- **Too many Dock restarts**: The script builds one dockutil 3 action batch, uses `--no-restart` for add/remove actions, and handles Dock restart in a controlled way.
- **Every user or one user**: `DOCK_TARGET_MODE` supports current user, current user home, all homes, a specific home, a specific plist, or the default user template.
- **Different student, staff, or technician layouts**: Admins can adjust arrays or use `customize_dock_items_for_user` for role-specific logic.
- **Did it actually work**: The script verifies the Dock with dockutil, retries once if needed, logs results, and writes the marker only after completion.

That makes it a practical community template: conservative by default, customizable where MacAdmins expect it, and opinionated about the parts that usually cause failures.

### How to Download the Marriott Library Script

After the Marriott Library `dock-management` repository is created, MacAdmins will be able to download the script in a few common ways.

**Web Browser**

1. Go to `https://github.com/univ-of-utah-marriott-library-apple/dock-management`.
2. Open `dock_setup_student_template.sh`.
3. Select **Download raw file** or **Raw**, then save the script locally.
4. Review the site configuration and Dock item arrays before deploying it.

**GitHub Download ZIP**

1. Go to `https://github.com/univ-of-utah-marriott-library-apple/dock-management`.
2. Select **Code**.
3. Select **Download ZIP**.
4. Unzip the archive and review `dock_setup_student_template.sh` and any included README before use.

**git CLI**

```bash
git clone https://github.com/univ-of-utah-marriott-library-apple/dock-management.git
cd dock-management
bash -n dock_setup_student_template.sh
```

The `bash -n` command checks shell syntax only. It does not run the script or modify the Dock.

## Where to Keep Learning

- dockutil GitHub repository: <https://github.com/kcrawford/dockutil>
- University of Utah - Marriott Library - Apple Infrastructure GitHub organization: <https://github.com/univ-of-utah-marriott-library-apple>
- Planned Marriott Library repository name: `dock-management`
- MacAdmins Foundation and Slack join page: <https://www.macadmins.org/>
- After joining the MacAdmins Slack, search for `#dock-management`.

The Dock is personal enough that users notice it and operational enough that admins need to manage it carefully. The best workflows respect both sides: make the Mac useful on first login, avoid breaking user choice afterward, and keep the implementation plain enough that another MacAdmin can inherit it without a treasure map.

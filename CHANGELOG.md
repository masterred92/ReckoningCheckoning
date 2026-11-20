# Changelog

## 1.0.1
- Fixed: in combat a hidden Reckoning buff could be read as 0 charges, so a fight could look like every stored charge had been spent. This client hides buff details from addons during combat unless the game marks a spell as always visible, and a hidden buff looks the same as no buff. A hidden count is now treated as unknown: the box shows `?/4` and nothing is counted from it.
- Reckoning Checkoning now checks what the client allows (at login, at the start of each fight and on `/reck debug`) and picks how to count: from the Reckoning buff when the game keeps it visible, otherwise from your own Seal of Command and Reckoning cast events if the game sends them. Extra attacks spent can only be seen from the buff, so without it they show as `?`, never as a made-up 0.
- If neither is available, the box says plainly that procs can't be counted on this client and shows Seal of Command (and Reckoning, if listed) damage and share from the game's damage meter after each fight.
- Fixed: Seal of Command procs that land at the same moment (for example on stored Reckoning swings) were merged into one. Each proc now counts; only the same cast event delivered twice is ignored.
- This detection follows the game's documented rules for this client and should work here; confirmation in game will come from players. `/reck debug` shows which method is active and what the client allows, which helps with bug reports.

## 1.0.0
- First release for WoW: Forever (Interface 16001, client 1.60.1).
- Reckoning: stored charges (0-4) as a big number and pips, charges gained and extra attacks spent per fight and session.
- Seal of Command: `COMMAND!` flash and a proc count for every rank.
- After each fight: Seal of Command damage, share and average per proc from Blizzard's own damage meter, and Reckoning's too if the meter lists it; otherwise "counting procs only".
- Holy-gold box that follows your talents: Protection leads with Reckoning, Retribution with Command, Holy shows both (`/reck mode` to choose).
- Chime when the Reckoning store fills or on a Command streak, on every proc, on a new best average, or off. Built-in game sounds only.
- Movable, resizable and lockable box (240x150 below the middle of the screen), only shown on Paladins. `/reck debug`, `/reck meter`, `/reck report`.

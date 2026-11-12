# Changelog

## 1.0.0
- First release for WoW: Forever (Interface 16001, client 1.60.1).
- Reckoning: stored charges (0-4) as a big number and pips, charges gained and extra attacks spent per fight and session.
- Seal of Command: `COMMAND!` flash and a proc count for every rank.
- After each fight: Seal of Command damage, share and average per proc from Blizzard's own damage meter, and Reckoning's too if the meter lists it; otherwise "counting procs only".
- Holy-gold box that follows your talents: Protection leads with Reckoning, Retribution with Command, Holy shows both (`/reck mode` to choose).
- Chime when the Reckoning store fills or on a Command streak, on every proc, on a new best average, or off. Built-in game sounds only.
- Movable, resizable and lockable box (240x150 below the middle of the screen), only shown on Paladins. `/reck debug`, `/reck meter`, `/reck report`.

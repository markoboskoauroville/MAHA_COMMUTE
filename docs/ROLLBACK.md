# The way back

MAHA COMMUTE adds an umbrella over three apps that already worked on
their own. Removing the umbrella does not remove them.

## Take away the umbrella, keep the three apps

    rm -f $PREFIX/bin/commute
    rm -rf ~/.maha.commute

`day.commute`, `night.commute` and `all.commute` go on working exactly
as they did before, with their own data, their own keys and their own
launchers untouched.

## Go back to an app's previous folder

Only night.commute clears its folder on install, and only that one has
a copy kept:

    rm -rf ~/.nightcommute
    cp -a ~/.maha.commute/backup/night.prev ~/.nightcommute

One copy is kept, the one from the last install.

## Take an app away and keep everything else

From the menu, `i`, then its number. Or by hand:

    rm -f $PREFIX/bin/day.commute

The data in `~/.commute` stays where it is until it is deleted on
purpose.

## Go back to the original installers

The three originals still install over this without help. They are what
they always were, and the only difference in the copies carried inside
the umbrella is the Google key, which was taken out.

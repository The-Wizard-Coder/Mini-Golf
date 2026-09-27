extends Node
class_name GameMode
## Which mode the game scene should run. Lives on the script (static) so it
## survives the menu -> game scene change.

## true = endless generated holes, false = the hand-authored campaign.
static var endless := false

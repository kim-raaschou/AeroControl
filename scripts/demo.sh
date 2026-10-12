#!/bin/zsh
# A demo desk for AeroControl: 45 TextEdit windows on workspaces 3-9 and 0, in tiles, accordion,
# dwindle and with floats; with your own, about 60 on 10 workspaces. TextEdit only: Script Editor
# reopens its untitled documents on the next launch, and Terminal can hang on closing.
#   scripts/demo.sh up      open them (focus jumps for half a minute: hands off the keyboard)
#   scripts/demo.sh strip   the TextEdit strip, as an app key would
#   scripts/demo.sh down    quit TextEdit without saving and put the focus back
set -u
state=${TMPDIR:-/tmp}/aerocontrol-demo

shape() {
  local ws=$1 kind=$2 ids
  aerospace flatten-workspace-tree --workspace $ws
  ids=($(aerospace list-windows --workspace $ws --format '%{window-id}'))
  case $kind in
    tiles) aerospace layout --workspace $ws --root h_tiles ;;
    vtiles) aerospace layout --workspace $ws --root v_tiles ;;
    accordion) aerospace layout --workspace $ws --root h_accordion ;;
    dwindle)
      aerospace layout --workspace $ws --root h_tiles
      for ((k = ${#ids} - 1; k >= 1; k--)); do aerospace join-with --window-id ${ids[$k]} right; done ;;
    floats)
      aerospace layout --workspace $ws --root h_tiles
      aerospace layout --window-id ${ids[1]} floating
      aerospace layout --window-id ${ids[2]} floating ;;
  esac
  aerospace balance-sizes --workspace $ws
}

case ${1:-} in
up)
  pgrep -xq TextEdit && { echo "TextEdit is running; quit it first, the demo quits it after."; exit 1; }
  mkdir -p $state
  aerospace list-windows --focused --format '%{window-id}' > $state/focus
  aerospace list-windows --all --format '%{window-id}' | sort > $state/before
  aerospace workspace 3
  for i in {1..45}; do
    osascript -e "tell application \"TextEdit\" to make new document with properties {text:\"AeroControl demo $i\"}"
    sleep 0.2
  done >/dev/null
  sleep 2
  new=($(comm -13 $state/before <(aerospace list-windows --all --format '%{window-id}' | sort)))
  plan=(3 4 5 6 7 8 9 0)
  for ((i = 1; i <= ${#new}; i++)); do aerospace move-node-to-workspace --window-id ${new[$i]} ${plan[$(( (i - 1) % 8 + 1 ))]} 2>/dev/null; done
  shape 3 tiles; shape 4 dwindle; shape 5 accordion; shape 6 vtiles
  shape 7 floats; shape 8 dwindle; shape 9 accordion; shape 0 tiles
  aerospace focus --window-id $(cat $state/focus)
  echo "$(aerospace list-windows --all --count) windows on $(aerospace list-workspaces --all | wc -l | tr -d ' ') workspaces."
  ;;
strip) [[ -f $state/focus ]] || { echo "Run $0 up first: without TextEdit windows the key starts TextEdit."; exit 1; }
  open "aerocontrol://app-id=com.apple.TextEdit" ;;
down)
  osascript -e 'tell application "TextEdit" to quit saving no'
  for _ in {1..25}; do aerospace list-windows --all --format '%{app-bundle-id}' | grep -q com.apple.TextEdit || break; sleep 0.2; done
  [[ -f $state/focus ]] && aerospace focus --window-id $(cat $state/focus)
  echo "$(aerospace list-windows --all --count) windows left."
  rm -rf $state
  ;;
*) echo "usage: $0 up | strip | down"; exit 2 ;;
esac 2>/dev/null

-----------------------------------------------------------------------------
-- |
-- Copyright   :  (c) Spencer Janssen 2007
-- License     :  BSD3-style (see LICENSE)
--
-- Maintainer  :  dons@galois.com
-- Stability   :  stable
-- Portability :  portable
--
-- This module specifies configurable defaults for xmonad. If you change
-- values here, be sure to recompile and restart (mod-q) xmonad,
-- for the changes to take effect.
--
------------------------------------------------------------------------

module XMonad.Config.Droundy where

--
-- Useful imports
--
import Control.Monad.Reader ( asks )

import XMonad hiding
    (workspaces,manageHook,numlockMask,keys,mouseBindings)
import qualified XMonad
    (workspaces,manageHook,numlockMask,keys,mouseBindings)

import XMonad.Layouts hiding ( (|||) )
import XMonad.Operations
import qualified XMonad.StackSet as W
import Data.Bits ((.|.))
import qualified Data.Map as M
import System.Exit
import Graphics.X11.Xlib
import XMonad.Core

-- % Extension-provided imports

import XMonad.Layout.Tabbed
import XMonad.Layout.Combo
import XMonad.Layout.LayoutCombinators
import XMonad.Layout.Square
import XMonad.Layout.LayoutScreens
import XMonad.Layout.WindowNavigation
import XMonad.Layout.NoBorders
import XMonad.Layout.WorkspaceDir
import XMonad.Layout.ToggleLayouts

import XMonad.Prompt
import XMonad.Prompt.Workspace
import XMonad.Prompt.Shell

import XMonad.Actions.CopyWindow
import XMonad.Actions.DynamicWorkspaces
import XMonad.Actions.RotView

myXPConfig :: XPConfig
myXPConfig = defaultXPConfig {font="-*-lucida-medium-r-*-*-14-*-*-*-*-*-*-*"
                             ,height=22}
 
-- | The default number of workspaces (virtual screens) and their names.
-- By default we use numeric strings, but any string may be used as a
-- workspace name. The number of workspaces is determined by the length
-- of this list.
--
-- A tagging example:
--
-- > workspaces = ["web", "irc", "code" ] ++ map show [4..9]
--
workspaces :: [WorkspaceId]
workspaces = ["1:mutt","2:iceweasel"]

-- | modMask lets you specify which modkey you want to use. The default
-- is mod1Mask ("left alt").  You may also consider using mod3Mask
-- ("right alt"), which does not conflict with emacs keybindings. The
-- "windows key" is usually mod4Mask.
--
modMask :: KeyMask
modMask = mod1Mask

-- | The mask for the numlock key. Numlock status is "masked" from the
-- current modifier status, so the keybindings will work with numlock on or
-- off. You may need to change this on some systems.
--
-- You can find the numlock modifier by running "xmodmap" and looking for a
-- modifier with Num_Lock bound to it:
--
-- > $ xmodmap | grep Num
-- > mod2        Num_Lock (0x4d)
--
-- Set numlockMask = 0 if you don't have a numlock key, or want to treat
-- numlock status separately.
--
numlockMask :: KeyMask
numlockMask = mod2Mask

-- | Default offset of drawable screen boundaries from each physical
-- screen. Anything non-zero here will leave a gap of that many pixels
-- on the given edge, on the that screen. A useful gap at top of screen
-- for a menu bar (e.g. 15)
--
-- An example, to set a top gap on monitor 1, and a gap on the bottom of
-- monitor 2, you'd use a list of geometries like so:
--
-- > defaultGaps = [(18,0,0,0),(0,18,0,0)] -- 2 gaps on 2 monitors
--
-- Fields are: top, bottom, left, right.
--
--defaultGaps :: [(Int,Int,Int,Int)]


------------------------------------------------------------------------
-- Window rules

-- | Execute arbitrary actions and WindowSet manipulations when managing
-- a new window. You can use this to, for example, always float a
-- particular program, or have a client always appear on a particular
-- workspace.
--
-- To find the property name associated with a program, use
--  xprop | grep WM_CLASS
-- and click on the client you're interested in.
--
manageHook :: Window -- ^ the new window to manage
           -> String -- ^ window title
           -> String -- ^ window resource name
           -> String -- ^ window resource class
           -> X (WindowSet -> WindowSet)

-- Always float various programs:
manageHook w _ _ c | c `elem` floats = fmap (W.float w . snd) (floatLocation w)
 where floats = ["MPlayer", "Gimp"]

-- Desktop panels and dock apps should be ignored by xmonad:
manageHook w _ n _ | n `elem` ignore = reveal w >> return (W.delete w)
 where ignore = ["gnome-panel", "desktop_window", "kicker", "kdesktop"]

-- Automatically send Firefox windows to the "web" workspace:
-- If a workspace named "web" doesn't exist, the window will appear on the
-- current workspace.
manageHook _ _ "Gecko" _ = return $ W.shift "web"

-- The default rule: return the WindowSet unmodified.  You typically do not
-- want to modify this line.
manageHook _ _ _ _ = return id

------------------------------------------------------------------------
-- Extensible layouts
--
-- You can specify and transform your layouts by modifying these values.
-- If you change layout bindings be sure to use 'mod-shift-space' after
-- restarting (with 'mod-q') to reset your layout state to the new
-- defaults, as xmonad preserves your old layout settings by default.
--

-- | The available layouts.  Note that each layout is separated by |||, which
-- denotes layout choice.
layout = -- tiled ||| Mirror tiled ||| Full
     -- Add extra layouts you want to use here:
     -- % Extension-provided layouts
     workspaceDir "~" $ windowNavigation $ toggleLayouts (noBorders Full) $
     noBorders mytab |||
     mytab <-/> combineTwo Square mytab mytab |||
     mytab <//> mytab
  where
     mytab = tabbed shrinkText defaultTConf

------------------------------------------------------------------------
-- Key bindings:

-- | The xmonad key bindings. Add, modify or remove key bindings here.
--
-- (The comment formatting character is used when generating the manpage)
--
keys :: M.Map (KeyMask, KeySym) (X ())
keys = M.fromList $
    -- launching and killing programs
    [ ((modMask .|. shiftMask, xK_Return), asks (terminal . config) >>= spawn) -- %! Launch terminal
    , ((modMask,               xK_p     ), spawn "exe=`dmenu_path | dmenu` && eval \"exec $exe\"") -- %! Launch dmenu
    , ((modMask .|. shiftMask, xK_p     ), spawn "gmrun") -- %! Launch gmrun
    , ((modMask .|. shiftMask, xK_c     ), kill) -- %! Close the focused window

    , ((modMask,               xK_space ), sendMessage NextLayout) -- %! Rotate through the available layout algorithms
    , ((modMask .|. shiftMask, xK_space ), setLayout $ Layout layout) -- %!  Reset the layouts on the current workspace to default

    , ((modMask,               xK_n     ), refresh) -- %! Resize viewed windows to the correct size

    -- move focus up or down the window stack
    , ((modMask,               xK_Tab   ), windows W.focusDown) -- %! Move focus to the next window
    , ((modMask,               xK_j     ), windows W.focusDown) -- %! Move focus to the next window
    , ((modMask,               xK_k     ), windows W.focusUp  ) -- %! Move focus to the previous window
    , ((modMask,               xK_m     ), windows W.focusMaster  ) -- %! Move focus to the master window

    -- modifying the window order
    , ((modMask,               xK_Return), windows W.swapMaster) -- %! Swap the focused window and the master window
    , ((modMask .|. shiftMask, xK_j     ), windows W.swapDown  ) -- %! Swap the focused window with the next window
    , ((modMask .|. shiftMask, xK_k     ), windows W.swapUp    ) -- %! Swap the focused window with the previous window

    -- resizing the master/slave ratio
    , ((modMask,               xK_h     ), sendMessage Shrink) -- %! Shrink the master area
    , ((modMask,               xK_l     ), sendMessage Expand) -- %! Expand the master area

    -- floating layer support
    , ((modMask,               xK_t     ), withFocused $ windows . W.sink) -- %! Push window back into tiling

    -- toggle the status bar gap
    , ((modMask              , xK_b     ), modifyGap (\i n -> let x = (defaultGaps defaultConfig ++ repeat (0,0,0,0)) !! i in if n == x then (0,0,0,0) else x)) -- %! Toggle the status bar gap

    -- quit, or restart
    , ((modMask .|. shiftMask, xK_Escape), io (exitWith ExitSuccess)) -- %! Quit xmonad
    , ((modMask              , xK_Escape), broadcastMessage ReleaseResources >> restart (Just "xmonad-droundy") True) -- %! Restart xmonad

    -- % Extension-provided key bindings

    , ((modMask .|. shiftMask, xK_z     ),
       layoutScreens 1 (fixedLayout [Rectangle 0 0 1024 768]))
    , ((modMask .|. shiftMask .|. controlMask, xK_z),
       layoutScreens 1 (fixedLayout [Rectangle 0 0 1440 900]))
    , ((modMask .|. shiftMask, xK_Right), rotView True)
    , ((modMask .|. shiftMask, xK_Left), rotView False)
    , ((modMask, xK_Right), sendMessage $ Go R)
    , ((modMask, xK_Left), sendMessage $ Go L)
    , ((modMask, xK_Up), sendMessage $ Go U)
    , ((modMask, xK_Down), sendMessage $ Go D)
    , ((modMask .|. controlMask, xK_Right), sendMessage $ Swap R)
    , ((modMask .|. controlMask, xK_Left), sendMessage $ Swap L)
    , ((modMask .|. controlMask, xK_Up), sendMessage $ Swap U)
    , ((modMask .|. controlMask, xK_Down), sendMessage $ Swap D)
    , ((modMask .|. controlMask .|. shiftMask, xK_Right), sendMessage $ Move R)
    , ((modMask .|. controlMask .|. shiftMask, xK_Left), sendMessage $ Move L)
    , ((modMask .|. controlMask .|. shiftMask, xK_Up), sendMessage $ Move U)
    , ((modMask .|. controlMask .|. shiftMask, xK_Down), sendMessage $ Move D)
 
    , ((0, xK_F2  ), spawn "gnome-terminal") -- %! Launch gnome-terminal
    , ((0, xK_F3  ), shellPrompt myXPConfig) -- %! Launch program
    , ((0, xK_F11   ), spawn "ksnapshot") -- %! Take snapshot
    , ((modMask .|. shiftMask, xK_x     ), changeDir myXPConfig)
    , ((modMask .|. shiftMask, xK_BackSpace), removeWorkspace)
    , ((modMask .|. shiftMask, xK_v     ), selectWorkspace myXPConfig)
    , ((modMask .|. shiftMask, xK_m     ), workspacePrompt myXPConfig (windows . copy))
    , ((modMask .|. shiftMask, xK_r), renameWorkspace myXPConfig)
    , ((modMask .|. controlMask, xK_space), sendMessage ToggleLayout)
    , ((modMask .|. controlMask, xK_f), sendMessage (JumpToLayout "Full"))
    ]
{-
    ++
    -- mod-[1..9] %! Switch to workspace N
    -- mod-shift-[1..9] %! Move client to workspace N
    [((m .|. modMask, k), windows $ f i)
        | (i, k) <- zip workspaces [xK_1 .. xK_9]
        , (f, m) <- [(W.greedyView, 0), (W.shift, shiftMask)]]
    ++
    -- mod-{w,e,r} %! Switch to physical/Xinerama screens 1, 2, or 3
    -- mod-shift-{w,e,r} %! Move client to screen 1, 2, or 3
    [((m .|. modMask, key), screenWorkspace sc >>= flip whenJust (windows . f))
        | (key, sc) <- zip [xK_w, xK_e, xK_r] [0..]
        , (f, m) <- [(W.view, 0), (W.shift, shiftMask)]]
-}
 
    -- % Extension-provided key bindings lists
 
    ++
    zip (zip (repeat modMask) [xK_F1..xK_F12]) (map (withNthWorkspace W.greedyView) [0..])
    ++
    zip (zip (repeat (modMask .|. shiftMask)) [xK_F1..xK_F12]) (map (withNthWorkspace copy) [0..])

-- | Mouse bindings: default actions bound to mouse events
--
mouseBindings :: M.Map (KeyMask, Button) (Window -> X ())
mouseBindings = M.fromList $
    -- mod-button1 %! Set the window to floating mode and move by dragging
    [ ((modMask, button1), (\w -> focus w >> mouseMoveWindow w))
    -- mod-button2 %! Raise the window to the top of the stack
    , ((modMask, button2), (\w -> focus w >> windows W.swapMaster))
    -- mod-button3 %! Set the window to floating mode and resize by dragging
    , ((modMask, button3), (\w -> focus w >> mouseResizeWindow w))
    -- you may also bind events to the mouse scroll wheel (button4 and button5)

    -- % Extension-provided mouse bindings
    ]

-- % Extension-provided definitions

defaultConfig :: XConfig
defaultConfig = XConfig { borderWidth = 1 -- Width of the window border in pixels.
                        , XMonad.workspaces = workspaces
                        , defaultGaps = [(0,0,0,0)] -- 15 for default dzen font
                        -- | The top level layout switcher. Most users will not need to modify this binding.
                        --
                        -- By default, we simply switch between the layouts listed in `layouts'
                        -- above, but you may program your own selection behaviour here. Layout
                        -- transformers, for example, would be hooked in here.
                        --
                        , layoutHook = Layout layout
                        , terminal = "xterm" -- The preferred terminal program.
                        , normalBorderColor = "#dddddd" -- Border color for unfocused windows.
                        , focusedBorderColor = "#00ff00" -- Border color for focused windows.
                        , XMonad.numlockMask = numlockMask
                        , XMonad.keys = keys
                        , XMonad.mouseBindings = mouseBindings
                        -- | Perform an arbitrary action on each internal state change or X event.
                        -- Examples include:
                        --      * do nothing
                        --      * log the state to stdout
                        --
                        -- See the 'DynamicLog' extension for examples.
                        , logHook = return ()
                        , XMonad.manageHook = manageHook
                        }

-- main :: IO ()
-- main = makeMain defaultConfig

{-# OPTIONS_GHC -fno-warn-missing-signatures #-}

-----------------------------------------------------------------------------
-- |
-- Module       : XMonad.Config.Desktop
-- Copyright    : (c) Spencer Janssen <spencerjanssen@gmail.com>
-- License      : BSD
--
-- Maintainer   : Spencer Janssen <spencerjanssen@gmail.com>
-- Stability    :  unstable
-- Portability  :  unportable
--
-- This module provides a config suitable for use with a desktop
-- environment such as KDE or GNOME.

module XMonad.Config.Desktop (
    desktopConfig,
    desktopLayoutModifiers
    ) where

import XMonad
import XMonad.Config (defaultConfig)
import XMonad.Hooks.ManageDocks
import XMonad.Hooks.EwmhDesktops

import qualified Data.Map as M

desktopConfig = defaultConfig
    { logHook    = ewmhDesktopsLogHook
    , layoutHook = desktopLayoutModifiers $ layoutHook defaultConfig
    , manageHook = manageHook defaultConfig <+> manageDocks
    , handleEventHook = ewmhDesktopsEventHook
    , keys       = \c -> desktopKeys c `M.union` keys defaultConfig c }

desktopKeys (XConfig {modMask = modm}) = M.fromList $
    [ ((modm, xK_b), sendMessage ToggleStruts) ]

desktopLayoutModifiers layout = avoidStruts layout

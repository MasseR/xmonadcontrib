{-# LANGUAGE MultiParamTypeClasses, FlexibleContexts #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  XMonad.Hooks.MessageHooks
-- Copyright   :  (c) Spencer Janssen 2007, Devin Mullins 2007
-- License     :  BSD3-style (see LICENSE)
--
-- Maintainer  :  Devin Mullins <me@twifkak.com>,
--                David Roundy <droundy@darcs.net>
-- Stability   :  experimental
-- Portability :  not portable, uses mtl, X11, posix
--
-- Provides an alternative main event loop that unifies event handlers into
-- the concept of a message filter chain. This module is experimental.
-- You'd have to be crazy to want to use it.
-----------------------------------------------------------------------------

-- This module was started by copying the entire contents of XMonad.Main. Any
-- future changes to the original module should be replicated here.

-- TODO:
--  * add state to messageHooks
--  * add messageHooks to the XConfig, if possible
--  * sendMessage should pass through the filter chain (broadcastMessage excepted)
--  * intercept broadcastMessage:
--  *  * don't export broadcastMessage:
--  *  * handle should just return True / False instead of calling broadcastMessage
--  *  * broadcastMessage should be the last filter called by processMessage
--  *  * users should be able to call broadcastMessage' (= processMessage $ messageHooks config)
--  * ability to schedule a message for delivery?
--  * ability to modify a message during transport?
--  * xmonad sends an InitMessage once?

module XMonad.Hooks.MessageHooks (xmonad) where

import Data.Bits
import qualified Data.Map as M
import qualified Data.Set as S
import Control.Monad.Reader
import Control.Monad.State
import Data.Maybe (fromMaybe)

import System.Environment (getArgs)

import Graphics.X11.Xlib hiding (refreshKeyboardMapping)
import Graphics.X11.Xlib.Extras
import Graphics.X11.Xinerama    (getScreenInfo)

import XMonad.Core
import XMonad.StackSet (new, floating, member)
import qualified XMonad.StackSet as W
import XMonad.Operations

import System.IO

-- True if message may continue; False to halt the filter chain.
type MessageHook = SomeMessage -> X Bool

-- |
-- The main entry point
--
xmonad :: (LayoutClass l Window, Read (l Window)) => [MessageHook] -> XConfig l -> IO ()
xmonad messageHooks initxmc = do
    -- First, wrap the layout in an existential, to keep things pretty:
    let xmc = initxmc { layoutHook = Layout $ layoutHook initxmc }
    dpy   <- openDisplay ""
    let dflt = defaultScreen dpy

    rootw  <- rootWindow dpy dflt
    xinesc <- getScreenInfo dpy
    nbc    <- initColor dpy $ normalBorderColor xmc
    fbc    <- initColor dpy $ focusedBorderColor xmc
    hSetBuffering stdout NoBuffering
    args <- getArgs

    let layout = layoutHook xmc
        lreads = readsLayout layout
        initialWinset = new layout (workspaces xmc) $ zipWith SD xinesc gaps

        maybeRead reads' s = case reads' s of
                                [(x, "")] -> Just x
                                _         -> Nothing

        winset = fromMaybe initialWinset $ do
                    ("--resume" : s : _) <- return args
                    ws                   <- maybeRead reads s
                    return . W.ensureTags layout (workspaces xmc)
                           $ W.mapLayout (fromMaybe layout . maybeRead lreads) ws

        gaps = take (length xinesc) $ defaultGaps xmc ++ repeat (0,0,0,0)

        cf = XConf
            { display       = dpy
            , config        = xmc
            , theRoot       = rootw
            , normalBorder  = nbc
            , focusedBorder = fbc
            , keyActions    = keys xmc xmc
            , buttonActions = mouseBindings xmc xmc }
        st = XState
            { windowset     = initialWinset
            , mapped        = S.empty
            , waitingUnmap  = M.empty
            , dragging      = Nothing }

    xSetErrorHandler -- in C, I'm too lazy to write the binding: dons

    -- setup initial X environment
    sync dpy False
    selectInput dpy rootw $  substructureRedirectMask .|. substructureNotifyMask
                         .|. enterWindowMask .|. leaveWindowMask .|. structureNotifyMask

    allocaXEvent $ \e ->
        runX cf st $ do

            grabKeys
            grabButtons

            io $ sync dpy False

            -- bootstrap the windowset, Operations.windows will identify all
            -- the windows in winset as new and set initial properties for
            -- those windows
            windows (const winset)

            -- scan for all top-level windows, add the unmanaged ones to the
            -- windowset
            ws <- io $ scan dpy rootw
            mapM_ manage ws

            -- main loop, for all you HOF/recursion fans out there.
            forever_ $ processMessage messageHooks . SomeMessage =<< io (nextEvent dpy e >> getEvent e)

    return ()
      where forever_ a = a >> forever_ a


processMessage :: [MessageHook] -> SomeMessage -> X ()
processMessage (mh : mhs) msg       = whenX (mh msg) $ processMessage mhs msg
processMessage []         msg
    | Just event <- fromMessage msg = handle event
processMessage []         _         = return ()

-- ---------------------------------------------------------------------
-- | Event handler. Map X events onto calls into Operations.hs, which
-- modify our internal model of the window manager state.
--
-- Events dwm handles that we don't:
--
--    [ButtonPress]    = buttonpress,
--    [Expose]         = expose,
--    [PropertyNotify] = propertynotify,
--
handle :: Event -> X ()

-- run window manager command
handle (KeyEvent {ev_event_type = t, ev_state = m, ev_keycode = code})
    | t == keyPress = withDisplay $ \dpy -> do
        s  <- io $ keycodeToKeysym dpy code 0
        mClean <- cleanMask m
        ks <- asks keyActions
        userCode $ whenJust (M.lookup (mClean, s) ks) id

-- manage a new window
handle (MapRequestEvent    {ev_window = w}) = withDisplay $ \dpy -> do
    wa <- io $ getWindowAttributes dpy w -- ignore override windows
    -- need to ignore mapping requests by managed windows not on the current workspace
    managed <- isClient w
    when (not (wa_override_redirect wa) && not managed) $ do manage w

-- window destroyed, unmanage it
-- window gone,      unmanage it
handle (DestroyWindowEvent {ev_window = w}) = whenX (isClient w) $ unmanage w

-- We track expected unmap events in waitingUnmap.  We ignore this event unless
-- it is synthetic or we are not expecting an unmap notification from a window.
handle (UnmapEvent {ev_window = w, ev_send_event = synthetic}) = whenX (isClient w) $ do
    e <- gets (fromMaybe 0 . M.lookup w . waitingUnmap)
    if (synthetic || e == 0)
        then unmanage w
        else modify (\s -> s { waitingUnmap = M.adjust pred w (waitingUnmap s) })

-- set keyboard mapping
handle e@(MappingNotifyEvent {}) = do
    io $ refreshKeyboardMapping e
    when (ev_request e == mappingKeyboard) grabKeys

-- handle button release, which may finish dragging.
handle e@(ButtonEvent {ev_event_type = t})
    | t == buttonRelease = do
    drag <- gets dragging
    case drag of
        -- we're done dragging and have released the mouse:
        Just (_,f) -> modify (\s -> s { dragging = Nothing }) >> f
        Nothing    -> broadcastMessage e

-- handle motionNotify event, which may mean we are dragging.
handle e@(MotionEvent {ev_event_type = _t, ev_x = x, ev_y = y}) = do
    drag <- gets dragging
    case drag of
        Just (d,_) -> d (fromIntegral x) (fromIntegral y) -- we're dragging
        Nothing -> broadcastMessage e

-- click on an unfocused window, makes it focused on this workspace
handle e@(ButtonEvent {ev_window = w,ev_event_type = t,ev_button = b })
    | t == buttonPress = do
    -- If it's the root window, then it's something we
    -- grabbed in grabButtons. Otherwise, it's click-to-focus.
    isr <- isRoot w
    m <- cleanMask $ ev_state e
    ba <- asks buttonActions
    if isr then userCode $ whenJust (M.lookup (m, b) ba) ($ ev_subwindow e)
           else focus w
    sendMessage e -- Always send button events.

-- entered a normal window, makes this focused.
handle e@(CrossingEvent {ev_window = w, ev_event_type = t})
    | t == enterNotify && ev_mode   e == notifyNormal
                       && ev_detail e /= notifyInferior = focus w

-- left a window, check if we need to focus root
handle e@(CrossingEvent {ev_event_type = t})
    | t == leaveNotify
    = do rootw <- asks theRoot
         when (ev_window e == rootw && not (ev_same_screen e)) $ setFocusX rootw

-- configure a window
handle e@(ConfigureRequestEvent {ev_window = w}) = withDisplay $ \dpy -> do
    ws <- gets windowset
    wa <- io $ getWindowAttributes dpy w

    bw <- asks (borderWidth . config)

    if M.member w (floating ws)
        || not (member w ws)
        then do io $ configureWindow dpy w (ev_value_mask e) $ WindowChanges
                    { wc_x            = ev_x e
                    , wc_y            = ev_y e
                    , wc_width        = ev_width e
                    , wc_height       = ev_height e
                    , wc_border_width = fromIntegral bw
                    , wc_sibling      = ev_above e
                    , wc_stack_mode   = ev_detail e }
                when (member w ws) (float w)
        else io $ allocaXEvent $ \ev -> do
                 setEventType ev configureNotify
                 setConfigureEvent ev w w
                     (wa_x wa) (wa_y wa) (wa_width wa)
                     (wa_height wa) (ev_border_width e) none (wa_override_redirect wa)
                 sendEvent dpy w False 0 ev
    io $ sync dpy False

-- configuration changes in the root may mean display settings have changed
handle (ConfigureEvent {ev_window = w}) = whenX (isRoot w) rescreen

-- property notify
handle PropertyEvent { ev_event_type = t, ev_atom = a }
    | t == propertyNotify && a == wM_NAME = userCode =<< asks (logHook . config)

handle e = broadcastMessage e -- trace (eventName e) -- ignoring


-- ---------------------------------------------------------------------
-- IO stuff. Doesn't require any X state
-- Most of these things run only on startup (bar grabkeys)

-- | scan for any new windows to manage. If they're already managed,
-- this should be idempotent.
scan :: Display -> Window -> IO [Window]
scan dpy rootw = do
    (_, _, ws) <- queryTree dpy rootw
    filterM ok ws
  -- TODO: scan for windows that are either 'IsViewable' or where WM_STATE ==
  -- Iconic
  where ok w = do wa <- getWindowAttributes dpy w
                  a  <- internAtom dpy "WM_STATE" False
                  p  <- getWindowProperty32 dpy a w
                  let ic = case p of
                            Just (3:_) -> True -- 3 for iconified
                            _          -> False
                  return $ not (wa_override_redirect wa)
                         && (wa_map_state wa == waIsViewable || ic)

-- | Grab the keys back
grabKeys :: X ()
grabKeys = do
    XConf { display = dpy, theRoot = rootw } <- ask
    let grab kc m = io $ grabKey dpy kc m rootw True grabModeAsync grabModeAsync
    io $ ungrabKey dpy anyKey anyModifier rootw
    ks <- asks keyActions
    forM_ (M.keys ks) $ \(mask,sym) -> do
         kc <- io $ keysymToKeycode dpy sym
         -- "If the specified KeySym is not defined for any KeyCode,
         -- XKeysymToKeycode() returns zero."
         when (kc /= '\0') $ mapM_ (grab kc . (mask .|.)) =<< extraModifiers

-- | XXX comment me
grabButtons :: X ()
grabButtons = do
    XConf { display = dpy, theRoot = rootw } <- ask
    let grab button mask = io $ grabButton dpy button mask rootw False buttonPressMask
                                           grabModeAsync grabModeSync none none
    io $ ungrabButton dpy anyButton anyModifier rootw
    ems <- extraModifiers
    ba <- asks buttonActions
    mapM_ (\(m,b) -> mapM_ (grab b . (m .|.)) ems) (M.keys $ ba)

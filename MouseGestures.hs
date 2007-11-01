-----------------------------------------------------------------------------
-- |
-- Module      :  XMonadContrib.MouseGestures
-- Copyright   :  (c) Lukas Mai
-- License     :  BSD3-style (see LICENSE)
-- 
-- Maintainer  :  <l.mai@web.de>
-- Stability   :  unstable
-- Portability :  unportable
--
-- Support for simple mouse gestures
--
-----------------------------------------------------------------------------

module XMonadContrib.MouseGestures (
    -- * Usage
    -- $usage
	Direction(..),
    mouseGesture
) where

import XMonad
import XMonad.Operations
import Graphics.X11.Xlib
import Graphics.X11.Xlib.Extras

import Control.Monad.Reader
import Data.IORef
import qualified Data.Map as M
import Data.Map (Map)

import System.IO

-- $usage
-- In your Config.hs:
--
-- > import XMonadContrib.MouseGestures
-- > ...
-- > mouseBindings = M.fromList $
-- >     [ ...
-- >     , ((modMask .|. shiftMask, button3), mouseGesture gestures)
-- >     ]
-- >     where
-- >     gestures = M.fromList
-- >         [ ([], focus)
-- >         , ([U], \w -> focus w >> windows W.swapUp)
-- >         , ([D], \w -> focus w >> windows W.swapDown)
-- >         , ([R, D], \_ -> sendMessage NextLayout)
-- >         ]
--
-- This is just an example, of course. You can use any mouse button and
-- gesture definitions you want.

data Direction = L | U | R | D
    deriving (Eq, Ord, Show, Read, Enum, Bounded)

type Pos = (Position, Position)

delta :: Pos -> Pos -> Position
delta (ax, ay) (bx, by) = max (d ax bx) (d ay by)
    where
    d a b = abs (a - b)

dir :: Pos -> Pos -> Direction
dir (ax, ay) (bx, by) = trans . (/ pi) $ atan2 (fromIntegral $ ay - by) (fromIntegral $ bx - ax)
    where
    trans :: Double -> Direction
    trans x
        | rg (-3/4) (-1/4) x = D
        | rg (-1/4)  (1/4) x = R
        | rg  (1/4)  (3/4) x = U
        | otherwise          = L
    rg a z x = a <= x && x < z

debugging :: Int
debugging = 0

collect :: IORef (Pos, [(Direction, Pos, Pos)]) -> Position -> Position -> X ()
collect st nx ny = do
    let np = (nx, ny)
    stx@(op, ds) <- io $ readIORef st
    when (debugging > 0) $ io $ putStrLn $ show "Mouse Gesture" ++ unwords (map show (extract stx)) ++ (if debugging > 1 then "; " ++ show op ++ "-" ++ show np else "")
    case ds of
        []
            | insignificant np op -> return ()
            | otherwise -> io $ writeIORef st (op, [(dir op np, np, op)])
        (d, zp, ap_) : ds'
            | insignificant np zp -> return ()
            | otherwise -> do
                let
                    d' = dir zp np
                    ds''
                        | d == d'   = (d, np, ap_) : ds'
                        | otherwise = (d', np, zp) : ds
                io $ writeIORef st (op, ds'')
    where
    insignificant a b = delta a b < 10

extract :: (Pos, [(Direction, Pos, Pos)]) -> [Direction]
extract (_, xs) = reverse . map (\(x, _, _) -> x) $ xs

mouseGesture :: Map [Direction] (Window -> X ()) -> Window -> X ()
mouseGesture tbl win = withDisplay $ \dpy -> do
    root <- asks theRoot
    let win' = if win == none then root else win
    acc <- io $ do
        qp@(_, _, _, ix, iy, _, _, _) <- queryPointer dpy win'
        when (debugging > 1) $ putStrLn $ show "queryPointer" ++ show qp
        when (debugging > 1 && win' == none) $ putStrLn $ show "mouseGesture" ++ "zomg none"
        newIORef ((fromIntegral ix, fromIntegral iy), [])
    mouseDrag (collect acc) $ do
        when (debugging > 0) $ io $ putStrLn $ show ""
        gest <- io $ liftM extract $ readIORef acc
        case M.lookup gest tbl of
            Nothing -> return ()
            Just f -> f win'

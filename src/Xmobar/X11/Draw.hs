{-# LANGUAGE CPP #-}
------------------------------------------------------------------------------
-- |
-- Module: Xmobar.X11.Draw
-- Copyright: (c) 2022 Jose Antonio Ortega Ruiz
-- License: BSD3-style (see LICENSE)
--
-- Maintainer: jao@gnu.org
-- Stability: unstable
-- Portability: unportable
-- Created: Fri Sep 09, 2022 02:03
--
-- Drawing the xmobar contents using Cairo and Pango
--
--
------------------------------------------------------------------------------

module Xmobar.X11.Draw (draw) where

import qualified Data.Map as M

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Foreign.C.Types as FT
import qualified Graphics.X11.Xlib as X11

import qualified Xmobar.Config.Types as C
import qualified Xmobar.Run.Parsers as P
import qualified Xmobar.X11.Bitmap as B
import qualified Xmobar.X11.Types as X
import qualified Xmobar.X11.CairoDraw as CD
import qualified Xmobar.X11.CairoSurface as CS

#ifdef XRENDER
import qualified Xmobar.X11.XRender as XRender
#endif

drawXBitmap :: X.XConf -> X11.GC -> X11.Pixmap -> CD.BitmapDrawer
drawXBitmap xconf gc p h v path = do
  let disp = X.display xconf
      conf = X.config xconf
      fc = C.fgColor conf
      bc = C.bgColor conf
  case lookupXBitmap xconf path of
    Just bm -> liftIO $ B.drawBitmap disp p gc fc bc (round h) (round v) bm
    Nothing -> return ()

lookupXBitmap :: X.XConf -> String -> Maybe B.Bitmap
lookupXBitmap xconf path = M.lookup path (X.iconCache xconf)

withPixmap :: X11.Display -> X11.Drawable -> X11.Rectangle -> FT.CInt
           -> (X11.GC -> X11.Pixmap -> IO a) -> IO a
withPixmap disp win (X11.Rectangle _ _ w h) depth action = do
  p <- X11.createPixmap disp win w h depth
  gc <- X11.createGC disp win
  X11.setGraphicsExposures disp gc False
  res <- action gc p
  -- copy the pixmap with the new string to the window
  X11.copyArea disp p win gc 0 0 w h 0 0
  -- free up everything (we do not want to leak memory!)
  X11.freeGC disp gc
  X11.freePixmap disp p
  -- resync (discard events, we don't read/process events from this display conn)
  X11.sync disp True
  return res

draw :: [[P.Segment]] -> X.X [X.ActionPos]
draw segments = do
  xconf <- ask
  let disp = X.display xconf
      win = X.window xconf
      rect@(X11.Rectangle _ _ w h) = X.rect xconf
      screen = X11.defaultScreenOfDisplay disp
      depth = X11.defaultDepthOfScreen screen
      vis = X11.defaultVisualOfScreen screen
      conf = X.config xconf

  liftIO $ withPixmap disp win rect depth $ \gc p -> do
    let bdraw = drawXBitmap xconf gc p
        blook = lookupXBitmap xconf
        dctx = CD.DC bdraw blook conf (fromIntegral w) (fromIntegral h) segments
        render = CD.drawSegments dctx

#ifdef XRENDER
        color = C.bgColor conf
        alph = C.alpha conf
    XRender.drawBackground disp p color alph (X11.Rectangle 0 0 w h)
#endif

    CS.withXlibSurface disp p vis (fromIntegral w) (fromIntegral h) render

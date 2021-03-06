module HaskellSetup where

{- This is the low-level stuff that hooks into the ncurses library, together
with the Haskell versions of the Agda types. You should not need to bother
reading or modifying this file. -}

import Debug.Trace
import Foreign
import Foreign.C (CInt(..))
import ANSIEscapes
import System.IO
import System.Environment
import Control.Applicative
import Control.Concurrent

foreign import ccall
  initscr :: IO () 

foreign import ccall "endwin"
  endwin :: IO CInt

foreign import ccall "refresh"
  refresh :: IO CInt

foreign import ccall "&LINES"
  linesPtr :: Ptr CInt

foreign import ccall "&COLS"
  colsPtr :: Ptr CInt

scrSize :: IO (Int, Int)
scrSize = do
    lnes <- peek linesPtr
    cols <- peek colsPtr
    return (fromIntegral cols, fromIntegral lnes)

data Modifier = Normal | Shift | Control deriving Show
data Key = Char Char | Arrow Modifier Direction | Enter | Backspace | Delete | Escape | Tab deriving Show
data Event = Key Key | Resize Nat Nat

data Nat = Zero | Suc Nat
toNat :: Int -> Nat
toNat 0 = Zero
toNat n = Suc (toNat (n - 1))
fromNat :: Nat -> Int
fromNat Zero = 0
fromNat (Suc n) = 1 + fromNat n

data Colour
  = Black | Red     | Green | Yellow
  | Blue  | Magenta | Cyan  | White

data Action
  = GoRowCol Nat Nat
  | SendText [Char]
  | Move Direction Nat
  | FgText Colour
  | BgText Colour

act :: Action -> IO ()
act (GoRowCol y x) = do
  resetCursor
  forward (fromNat x)
  down (fromNat y)
act (SendText s) = putStr s
act (Move d n) = moveCursor d (fromNat n)
act (FgText Black)   = escape "0;30m"
act (FgText Red)     = escape "1;31m"
act (FgText Green)   = escape "1;32m"
act (FgText Yellow)  = escape "1;33m"
act (FgText Blue)    = escape "1;34m"
act (FgText Magenta) = escape "1;35m"
act (FgText Cyan)    = escape "1;36m"
act (FgText White)   = escape "1;37m"
act (BgText Black)   = escape "40m"
act (BgText Red)     = escape "41m"
act (BgText Green)   = escape "42m"
act (BgText Yellow)  = escape "43m"
act (BgText Blue)    = escape "44m"
act (BgText Magenta) = escape "45m"
act (BgText Cyan)    = escape "46m"
act (BgText White)   = escape "47m"

getEscapeKey :: [(String, Key)] -> IO (Maybe Key)
getEscapeKey [] = return Nothing
getEscapeKey sks = case lookup "" sks of
  Just k -> return (Just k)
  _ -> do
    c <- getChar
    getEscapeKey [(cs, k) | (d : cs, k) <- sks, d == c]

directions :: [(Char, Direction)]
directions = [('A', DU), ('B', DD),
              ('C', DR), ('D', DL)]

escapeKeys :: [(String, Key)]
escapeKeys =
  [([c], Arrow Normal d) | (c, d) <- directions] ++
  [("1;2" ++ [c], Arrow Shift d) | (c, d) <- directions] ++
  [("1;5" ++ [c], Arrow Control d) | (c, d) <- directions] ++
  [("3~", Delete)]

keyReady :: IO (Maybe Key)
keyReady = do
  b <- hReady stdin
  if not b then return Nothing else do
    c <- getChar
    case c of
      '\n' -> return $ Just Enter
      '\r' -> return $ Just Enter
      '\b' -> return $ Just Backspace
      '\DEL' -> return $ Just Backspace
      '\t' -> return $ Just Tab
      _ | c >= ' ' -> return $ Just (Char c)
      '\ESC' -> do
        b <- hReady stdin
        if not b then return $ Just Escape else do
          c <- getChar
          case c of
            '[' -> getEscapeKey escapeKeys
            _ -> return $ Just Escape
      _ -> return $ Nothing

pni :: (Int, Int) -> (Nat, Nat)
pni (y, x) = (toNat y, toNat x)

mainLoop ::
  s -> (Event -> s -> (s, [Action])) ->
  IO ()
mainLoop start reactor = do
  hSetBuffering stdout NoBuffering
  hSetBuffering stdin NoBuffering
  initscr
  innerLoop (0, 0) start
  endwin
  return ()
  where
    innerLoop oldSize state0 = do
      refresh
      size@(w, h) <- scrSize
      let (state1, acts) = if size /= oldSize
            then reactor (Resize (toNat w) (toNat h)) state0
            else (state0, [])
      mapM_ act acts
      mc <- keyReady
      case mc of
        Nothing -> threadDelay 100 >> innerLoop size state1
        Just k -> do
          let (state2, acts) = reactor (Key k) state1
          mapM_ act acts
          innerLoop size state2

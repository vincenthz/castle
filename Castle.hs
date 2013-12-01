{-# LANGUAGE OverloadedStrings #-}


module Main where


import           Data.Monoid
import qualified Data.Text                 as T
import           Data.Tree
import           Filesystem
import           Filesystem.Path.CurrentOS as FS
import           Options.Applicative
import qualified Options.Applicative       as O
import           Prelude                   hiding (FilePath)
import           Shelly
import qualified Shelly                    as S


-- Settings

castleDir :: IO FilePath
castleDir = (FS.</> ".castle") <$> getHomeDirectory

-- Shell utilities

cabal_ :: T.Text -> [T.Text] -> Sh ()
cabal_ = command1_ "cabal" []

sandbox_ :: T.Text -> [T.Text] -> Sh ()
sandbox_ cmd = cabal_ "sandbox" . (cmd:)

-- Workflow functions

installCastle :: Sh ()
installCastle = do
    castle <- liftIO castleDir
    chdir (parent castle) $ do
        mkdirTree $ (filename castle) # leaves ["castles"]
    where (#)    = Node
          leaves = map (# [])

-- Command functions

castleList :: Sh ()
castleList =   liftIO (fmap (FS.</> "castles") castleDir)
           >>= ls
           >>= mapM_ (echo . toTextIgnore . basename)

castleNew :: T.Text -> Sh ()
castleNew castleName = do
    sandboxDir <- liftIO $ fmap ( (FS.</> S.fromText castleName)
                                . (FS.</> "castles"))
                                castleDir
    exists     <- test_d sandboxDir
    if exists
        then errorExit $ "Sandbox " <> castleName <> " already exists."
        else
            mkdir_p sandboxDir >> chdir sandboxDir
                (sandbox_ "init" ["--sandbox=" <> toTextIgnore sandboxDir])

-- Main

main :: IO ()
main = do
    cfg <- execParser opts

    shelly $ verbosely $ do
        installCastle

        case mode cfg of
            ListCmd           -> castleList
            NewCmd castleName -> castleNew castleName

    where
        opts' =   CastleOpts
              <$> subparser (  O.command "list" listCmd
                            <> O.command "new"  newCmd
                            )

        listCmd = pinfo (pure ListCmd) "List sand castles." mempty
        newCmd  = pinfo (NewCmd <$> textOption (  short 'n' <> long "name"
                                               <> metavar "CASTLE_NAME"
                                               <> help "The castle name to create."))
                        "Create a new castle." mempty

        opts    = pinfo opts' "Manage shared cabal sandboxes."
                        (header "castle - manage shared cabal sandboxes.")

-- Command-line parsing

-- | This is a builder utility for ParserInfo instances.
pinfo :: Parser a -> String -> InfoMod a -> ParserInfo a
pinfo p desc imod = info (helper <*> p)
                         (fullDesc <> progDesc desc <> imod)

textOption :: Mod OptionFields T.Text -> Parser T.Text
textOption fields = nullOption (reader (pure . T.pack) <> fields)

fileOption :: Mod OptionFields FilePath -> Parser FilePath
fileOption fields = nullOption (reader (pure . decodeString) <> fields)

data CastleOpts
        = CastleOpts
        { mode :: CastleCmd
        } deriving (Show)

data CastleCmd
        = ListCmd
        | NewCmd { castleName :: T.Text }
        deriving (Show)


{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE StrictData        #-}
-- | @travis.yaml@ structure.
module HaskellCI.Travis.Yaml where

import HaskellCI.Prelude

import qualified Data.Aeson         as Aeson
import qualified Data.List.NonEmpty as NE

import HaskellCI.Config.Ubuntu
import HaskellCI.List
import HaskellCI.Sh
import HaskellCI.YamlSyntax

-------------------------------------------------------------------------------
-- Data
-------------------------------------------------------------------------------

data Travis = Travis
    { travisUbuntu        :: !Ubuntu
    , travisLanguage      :: !String
    , travisGit           :: !TravisGit
    , travisCache         :: !TravisCache
    , travisBranches      :: !TravisBranches
    , travisNotifications :: !TravisNotifications
    , travisServices      :: ![String]
    , travisAddons        :: !TravisAddons
    , travisMatrix        :: !TravisMatrix
    , travisBeforeCache   :: ![Sh]
    , travisBeforeInstall :: ![Sh]
    , travisInstall       :: ![Sh]
    , travisScript        :: ![Sh]
    }
  deriving Show

newtype TravisGit = TravisGit
    { tgSubmodules :: Bool
    }
  deriving Show

newtype TravisCache = TravisCache
    { tcDirectories :: [FilePath]
    }
  deriving Show

newtype TravisBranches = TravisBranches
    { tbOnly :: [String]
    }
  deriving Show

data TravisNotifications = TravisNotifications
    { tnIRC   :: Maybe TravisIRC
    , tnEmail :: Bool
    }
  deriving Show

data TravisIRC = TravisIRC
    { tiChannels :: [String]
    , tiSkipJoin :: Bool
    , tiTemplate :: [String]
    , tiNick     :: Maybe String
    , tiPassword :: Maybe String
    }
  deriving Show

data TravisMatrix = TravisMatrix
    { tmInclude       :: [TravisJob]
    , tmAllowFailures :: [TravisAllowFailure]
    }
  deriving Show

data TravisJob = TravisJob
    { tjCompiler :: String
    , tjEnv      :: Maybe String
    , tjAddons   :: TravisAddons
    , tjOS       :: String
    }
  deriving Show

data TravisAddons = TravisAddons
    { taApt          :: TravisApt
    , taPostgres     :: Maybe String
    , taGoogleChrome :: Bool
    }
  deriving Show

data TravisApt = TravisApt
    { taPackages :: [String]
    , taSources  :: [TravisAptSource]
    }
  deriving Show

data TravisAptSource
    = TravisAptSource String
    | TravisAptSourceLine String (Maybe String) -- ^ sourceline with optional key
  deriving Show

newtype TravisAllowFailure = TravisAllowFailure
    { tafCompiler :: String
    }
  deriving Show

-------------------------------------------------------------------------------
-- Serialisation helpers (move to Travis.Yaml?)
-------------------------------------------------------------------------------

(^^^) :: ([String], String, Yaml [String]) -> String -> ([String], String, Yaml [String])
(a,b,c) ^^^ d = (d : a, b, c)

shListToYaml :: [Sh] -> Yaml [String]
shListToYaml shs = YList [] $ concat
    [ YString cs x : map fromString xs
    | (cs, x :| xs) <- gr shs
    ]
  where
    gr :: [Sh] -> [([String], NonEmpty String)]
    gr [] = []
    gr (Sh x : rest) = case gr rest of
        ([], xs) : xss -> ([], NE.cons x xs) : xss
        xss            -> ([], pure x) : xss

    gr (Comment c : rest) = case gr rest of
        (cs, xs) : xss -> (c : cs, xs) : xss
        []             -> [] -- end of comments are lost

-------------------------------------------------------------------------------
-- ToYaml
-------------------------------------------------------------------------------

instance ToYaml Travis where
    toYaml Travis {..} = ykeyValuesFilt []
        -- version forces validation
        -- https://blog.travis-ci.com/2019-10-24-build-config-validation
        [ "version"        ~> fromString "~> 1.0"
        , "language"       ~> fromString travisLanguage
        , "os"             ~> fromString "linux"
        , "dist"           ~> fromString (showUbuntu travisUbuntu)
        , "git"            ~> toYaml travisGit
        , "branches"       ~> toYaml travisBranches
        , "notifications"  ~> toYaml travisNotifications
        , "services"       ~> YList [] (map fromString travisServices)
        , "addons"         ~> toYaml travisAddons
        , "cache"          ~> toYaml travisCache
        , "before_cache"   ~> shListToYaml travisBeforeCache
        , "jobs"           ~> toYaml travisMatrix
        , "before_install" ~> shListToYaml travisBeforeInstall
        , "install"        ~> shListToYaml travisInstall
        , "script"         ~> shListToYaml travisScript
        ]

instance ToYaml TravisGit where
    toYaml TravisGit {..} = ykeyValuesFilt []
        [ "submodules" ~> toYaml tgSubmodules
          ^^^ "whether to recursively clone submodules"
        ]

instance ToYaml TravisBranches where
    toYaml TravisBranches {..} = ykeyValuesFilt []
        [ "only" ~> ylistFilt [] (map fromString tbOnly)
        ]

instance ToYaml TravisNotifications where
    toYaml TravisNotifications {..} = ykeyValuesFilt [] $ buildList $ do
        for_ tnIRC $ \y -> item $ "irc" ~> toYaml y
        unless tnEmail $ item $ "email" ~> toYaml False

instance ToYaml TravisIRC where
    toYaml TravisIRC {..} = ykeyValuesFilt [] $ buildList $ do
        item $ "channels"  ~> YList [] (map fromString tiChannels)
        item $ "skip_join" ~> toYaml tiSkipJoin
        item $ "template"  ~> YList [] (map fromString tiTemplate)
        for_ tiNick $ \n ->
            item $ "nick" ~> fromString n
        for_ tiPassword $ \p ->
            item $ "password" ~> fromString p

instance ToYaml TravisCache where
    toYaml TravisCache {..} = ykeyValuesFilt []
        [ "directories" ~> ylistFilt []
            [ fromString d
            | d <- tcDirectories
            ]
        ]

instance ToYaml TravisMatrix where
    toYaml TravisMatrix {..} = ykeyValuesFilt []
        [ "include"        ~> ylistFilt [] (map toYaml tmInclude)
        , "allow_failures" ~> ylistFilt [] (map toYaml tmAllowFailures)
        ]

instance ToYaml TravisJob where
    toYaml TravisJob {..} = ykeyValuesFilt [] $ buildList $ do
        item $ "compiler" ~> fromString tjCompiler
        item $ "addons"   ~> toYaml (Aeson.toJSON tjAddons)
        for_ tjEnv $ \e ->
            item $ "env" ~> fromString e
        item $ "os" ~> fromString tjOS

instance ToYaml TravisAllowFailure where
    toYaml TravisAllowFailure {..} = ykeyValuesFilt []
        [ "compiler" ~> fromString tafCompiler
        ]

instance ToYaml TravisAddons where
    toYaml TravisAddons {..} = ykeyValuesFilt [] $ buildList $ do
        -- no apt on purpose
        for_ taPostgres $ \p ->
            item $ "postgresql" ~> fromString p
        when taGoogleChrome $
            item $ "google" ~> fromString "stable"

-------------------------------------------------------------------------------
-- ToJSON
-------------------------------------------------------------------------------

instance Aeson.ToJSON TravisAddons where
    -- no postgresql on purpose
    toJSON TravisAddons {..} = Aeson.object
        [ "apt" Aeson..= taApt
        ]

instance Aeson.ToJSON TravisApt where
    toJSON TravisApt {..} = Aeson.object
        [ "packages" Aeson..= taPackages
        , "sources"  Aeson..= taSources
        ]

instance Aeson.ToJSON TravisAptSource where
    toJSON (TravisAptSource s) = Aeson.toJSON s
    toJSON (TravisAptSourceLine sl Nothing) = Aeson.object
        [ "sourceline" Aeson..= sl
        ]
    toJSON (TravisAptSourceLine sl (Just key_url)) = Aeson.object
        [ "sourceline" Aeson..= sl
        , "key_url"    Aeson..= key_url
        ]

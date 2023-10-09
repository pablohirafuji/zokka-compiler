{-# OPTIONS_GHC -Wall #-}
module Stuff
  ( details
  , interfaces
  , objects
  , prepublishDir
  , elmi
  , elmo
  , temp
  , findRoot
  , withRootLock
  , withRegistryLock
  , PackageCache
  , ZelmSpecificCache
  , getPackageCache
  , getZelmCache
  , registry
  , package
  , getReplCache
  , getElmHome
  , getOrCreateZelmCustomRepositoryConfig
  , getOrCreateZelmCacheDir
  , ZelmCustomRepositoryConfigFilePath(..)
  )
  where


import qualified System.Directory as Dir
import qualified System.Environment as Env
import qualified System.FileLock as Lock
import qualified System.FilePath as FP
import System.FilePath ((</>), (<.>))

import qualified Elm.ModuleName as ModuleName
import qualified Elm.Package as Pkg
import qualified Elm.Version as V



-- PATHS


stuff :: FilePath -> FilePath
stuff root =
  root </> "elm-stuff" </> customCompilerVersion
  where
    -- We need a custom compiler version because of Zelm's support for dependency
    -- overrides. If we override dependencies, we could end up with what appears to
    -- be an invalid cache for the vanilla Elm compiler, because we will have
    -- resolved a different set of dependencies than what the vanilla Elm compiler
    -- would have, which can result in interface files that do not correspond to
    -- elm.json as the vanilla Elm compiler understands the dependencies from 
    -- elm.json. This means that an end user who uses Zelm and then tries to revert
    -- back to using Elm could observe non-obvious breakage (even though it's 
    -- easily fixable by just deleting the elm-stuff directory), which we are trying
    -- to minimimze.
    --
    -- As far as I know no Elm IDE integration tools use the elm-stuff directory for
    -- important analyses. If that's not true, then we may revert to using the usual
    -- compiler version and just letting the user delete elm-stuff manually (the
    -- error message at least will tell them to delete the directory).
    customCompilerVersion = compilerVersion ++ "-zelm"


details :: FilePath -> FilePath
details root =
  stuff root </> "d.dat"


interfaces :: FilePath -> FilePath
interfaces root =
  stuff root </> "i.dat"


objects :: FilePath -> FilePath
objects root =
  stuff root </> "o.dat"


prepublishDir :: FilePath -> FilePath
prepublishDir root =
  stuff root </> "prepublish"


compilerVersion :: FilePath
compilerVersion =
  V.toChars V.compiler



-- ELMI and ELMO


elmi :: FilePath -> ModuleName.Raw -> FilePath
elmi root name =
  toArtifactPath root name "elmi"


elmo :: FilePath -> ModuleName.Raw -> FilePath
elmo root name =
  toArtifactPath root name "elmo"


toArtifactPath :: FilePath -> ModuleName.Raw -> String -> FilePath
toArtifactPath root name ext =
  stuff root </> ModuleName.toHyphenPath name <.> ext



-- TEMP


temp :: FilePath -> String -> FilePath
temp root ext =
  stuff root </> "temp" <.> ext



-- ROOT


findRoot :: IO (Maybe FilePath)
findRoot =
  do  dir <- Dir.getCurrentDirectory
      findRootHelp (FP.splitDirectories dir)


findRootHelp :: [String] -> IO (Maybe FilePath)
findRootHelp dirs =
  case dirs of
    [] ->
      return Nothing

    _:_ ->
      do  exists <- Dir.doesFileExist (FP.joinPath dirs </> "elm.json")
          if exists
            then return (Just (FP.joinPath dirs))
            else findRootHelp (init dirs)



-- LOCKS


withRootLock :: FilePath -> IO a -> IO a
withRootLock root work =
  do  let dir = stuff root
      Dir.createDirectoryIfMissing True dir
      Lock.withFileLock (dir </> "lock") Lock.Exclusive (\_ -> work)


-- We keep the same lock as in vanilla Elm because we are writing to the same package cache
withRegistryLock :: PackageCache -> IO a -> IO a
withRegistryLock (PackageCache dir) work =
  Lock.withFileLock (dir </> "lock") Lock.Exclusive (\_ -> work)



-- PACKAGE CACHES


newtype PackageCache = PackageCache FilePath

newtype ZelmSpecificCache = ZelmSpecificCache FilePath


getPackageCache :: IO PackageCache
getPackageCache =
  PackageCache <$> getCacheDir "packages"


getZelmCache :: IO ZelmSpecificCache
getZelmCache =
  ZelmSpecificCache <$> getOrCreateZelmCacheDir


registry :: ZelmSpecificCache -> FilePath
registry (ZelmSpecificCache dir) =
  dir </> "zelm-registry.dat"


package :: PackageCache -> Pkg.Name -> V.Version -> FilePath
package (PackageCache dir) name version =
  dir </> Pkg.toFilePath name </> V.toChars version



-- CACHE


getReplCache :: IO FilePath
getReplCache =
  getCacheDir "repl"


getCacheDir :: FilePath -> IO FilePath
getCacheDir projectName =
  do  home <- getElmHome
      let root = home </> compilerVersion </> projectName
      Dir.createDirectoryIfMissing True root
      return root


getElmHome :: IO FilePath
getElmHome =
  do  maybeCustomHome <- Env.lookupEnv "ELM_HOME"
      case maybeCustomHome of
        Just customHome -> return customHome
        Nothing -> Dir.getAppUserDataDirectory "elm"


-- The Zelm cache directory contains the Zelm-specific registry file, while the
-- Zelm directory proper contains the custom repository configuration (and hence 
-- is a bit more valuable than just the cache).
getOrCreateZelmCacheDir :: IO FilePath
getOrCreateZelmCacheDir = do
    cacheDir <- getCacheDir "zelm-cache"
    Dir.createDirectoryIfMissing True cacheDir
    pure cacheDir


getZelmDir :: IO FilePath
getZelmDir = getCacheDir "zelm"


newtype ZelmCustomRepositoryConfigFilePath = ZelmCustomRepositoryConfigFilePath { unZelmCustomRepositoryConfigFilePath :: FilePath }


getOrCreateZelmCustomRepositoryConfig :: IO ZelmCustomRepositoryConfigFilePath
getOrCreateZelmCustomRepositoryConfig =
  do
    zelmDir <- getZelmDir
    Dir.createDirectoryIfMissing True zelmDir
    pure $ ZelmCustomRepositoryConfigFilePath (zelmDir </> "custom-package-repository-config.json")

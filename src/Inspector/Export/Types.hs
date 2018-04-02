{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Inspector.Export.Types
    ( OutputType(..)
    , Inspectable(..)
    , builderToString
    , createEntry
    , fromEntry
    , checkEntryType

    , withBoolean
    , withInteger
    , withDouble
    , withString
    , withCollection
    , withStructure
    ) where

import Foundation
import Foundation.String (fromBytesUnsafe)
import Foundation.String.Builder

import Basement.Block (Block)
import Basement.Nat
import Data.ByteArray (Bytes, convert)
import Data.ByteArray.Encoding

import Crypto.Hash (Digest, digestFromByteString)
import Crypto.Hash.IO (HashAlgorithm(..))
import Crypto.MAC.HMAC (HMAC(..))

import Control.Applicative (Alternative(..))
import Control.Monad (mapM)
import Data.Typeable
import GHC.ST (runST)

import           Inspector.TestVector.Types      (Type)
import qualified Inspector.TestVector.Types as Type
import           Inspector.TestVector.Key        (Key)
import           Inspector.TestVector.Value      (Value)
import qualified Inspector.TestVector.Value as Value
import           Inspector.TestVector.TestVector (Entry(..))

builderToString :: Builder -> String
builderToString a = runST (runUnsafe a)

data OutputType
    = TestVector
    | Markdown
    | Rust
  deriving (Show, Eq, Ord, Enum, Bounded, Typeable)

reportError :: String -> Value -> Either String a
reportError desc it = Left $ case it of
    Value.Boolean    b   -> mkError $ "Received a boolean of value " <> show b
    Value.Integer    i   -> mkError $ "Received an integer of value " <> show i
    Value.Floating   d   -> mkError $ "Received an double of value " <> show d
    Value.String     str -> mkError $ "Received a string of value " <> show str
    Value.Array      col -> mkError $ "Received a collection of " <> show col
    Value.Object     str -> mkError $ "Received an object " <> show str
  where
    mkError :: String -> String
    mkError more = "Error when parsing " <> desc <> ". " <> more

withBoolean :: String -> (Bool -> Either String a) -> Value -> Either String a
withBoolean _ f (Value.Boolean b) = f b
withBoolean t _ r                 = reportError t r

withInteger :: String -> (Integer -> Either String a) -> Value -> Either String a
withInteger _ f (Value.Integer i) = f i
withInteger t _ r                 = reportError t r

withDouble :: String -> (Double -> Either String a) -> Value -> Either String a
withDouble _ f (Value.Floating i) = f i
withDouble t _ r                  = reportError t r

withString :: String -> (String -> Either String a) -> Value -> Either String a
withString _ f (Value.String str) = f str
withString t _ r                  = reportError t r

withCollection :: String -> (Value.Array -> Either String a) -> Value -> Either String a
withCollection _ f (Value.Array its) = f its
withCollection t _ r                 = reportError t r

withStructure :: String -> (Value.Object -> Either String a) -> Value -> Either String a
withStructure _ f (Value.Object nits) = f nits
withStructure t _ r                   = reportError t r

class Inspectable a where
    documentation :: Proxy a -> String

    -- | this is the type of export, one of the type, close to representation
    -- that is understood by the different `OutputType`
    --
    exportType :: Proxy a -> Type

    -- | reconstruct the object from the given value
    parser :: Value -> Either String a

    -- | seralise the object into a value
    builder :: a -> Value

createEntry :: forall a . Inspectable a => Key -> a -> Entry (Type, Value)
createEntry k v = Entry
    { entryKey = k
    , entryType = t
    , entryValue = v'
    , entryExtra = (t, v')
    }
  where
    t = exportType (Proxy @a)
    v' = builder v

checkEntryType :: Inspectable a => Proxy a -> Entry () -> Entry (Type, Value)
checkEntryType p e = Entry
    { entryKey = entryKey e
    , entryType = entryType e
    , entryValue = entryValue e
    , entryExtra = (t, liftValue t (entryValue e))
    }
  where
    t = exportType p

fromEntry :: Inspectable a
          => Proxy a
          -> Entry (Type, Value)
          -> Either String a
fromEntry _ e = first show $ parser (snd $ entryExtra e)

liftValue :: Type -> Value -> Value
liftValue t v
    | Type.isByteArray t = toByteArray v
    | otherwise          = v

toByteArray :: Value -> Value
toByteArray (Value.String str)
    | and (isHex <$> toList str) = builder $ toList (either (error . fromList) id (convertFromBase Base16 str) :: Block Word8)
    | otherwise                  = builder (convert str :: Bytes)
toByteArray v = v

isHex :: Char -> Bool
isHex c = c `elem` (['a'..'f'] <> ['A'..'F'] <> ['0'..'9'])

instance Inspectable Bool where
    documentation _ = "Boolean value, either true or false."
    exportType _ = Type.Boolean
    parser = withBoolean "Bool" pure
    builder = Value.Boolean
instance Inspectable Int8 where
    documentation _ = "8 bits signed integer."
    exportType _ = Type.Signed8
    parser = withInteger "Int8" (pure . fromInteger)
    builder  = Value.Integer . toInteger
instance Inspectable Int16 where
    documentation _ = "16 bits signed integer."
    exportType _ = Type.Signed16
    parser = withInteger "Int16" (pure . fromInteger)
    builder  = Value.Integer . toInteger
instance Inspectable Int32 where
    documentation _ = "32 bits signed integer."
    exportType _ = Type.Signed32
    parser = withInteger "Int32" (pure . fromInteger)
    builder  = Value.Integer . toInteger
instance Inspectable Int64 where
    documentation _ = "64 bits signed integer."
    exportType _ = Type.Signed64
    parser = withInteger "Int64" (pure . fromInteger)
    builder  = Value.Integer . toInteger
instance Inspectable Int where
    documentation _ = "signed integer."
    exportType _ = Type.Signed64
    parser = withInteger "Int" (pure . fromInteger)
    builder  = Value.Integer . toInteger
instance Inspectable Integer where
    documentation _ = "signed unbounded integer"
    exportType _ = Type.Signed64
    parser = withInteger "Integer" (pure . fromInteger)
    builder  = Value.Integer
instance Inspectable Word8 where
    documentation _ = "8 bits unsigned integer."
    exportType _ = Type.Unsigned8
    parser = withInteger "Word8" (pure . fromInteger)
    builder  = Value.Integer . toInteger
instance Inspectable Word16 where
    documentation _ = "16 bits unsigned integer."
    exportType _ = Type.Unsigned16
    parser = withInteger "Word16" (pure . fromInteger)
    builder  = Value.Integer . toInteger
instance Inspectable Word32 where
    documentation _ = "32 bits unsigned integer."
    exportType _ = Type.Unsigned32
    parser = withInteger "Word32" (pure . fromInteger)
    builder  = Value.Integer . toInteger
instance Inspectable Word64 where
    documentation _ = "64 bits unsigned integer."
    exportType _ = Type.Unsigned64
    parser = withInteger "Word64" (pure . fromInteger)
    builder  = Value.Integer . toInteger
instance Inspectable Word where
    documentation _ = "unsigned integer."
    exportType _ = Type.Unsigned64
    parser = withInteger "Word" (pure . fromInteger)
    builder  = Value.Integer . toInteger
instance Inspectable Double where
    documentation _ = "64 bits float."
    exportType _ = Type.Float64
    parser = withDouble "Double" pure
    builder  = Value.Floating
instance Inspectable String where
    documentation _ = "Bouble quoted, encoded string."
    exportType _ = Type.String
    parser = withString "String" pure
    builder  = Value.String
instance Inspectable (Block Word8) where
    documentation _ = "hexadecimal encoded bytes"
    exportType _ = Type.Array (Type.UnsizedArray Type.Unsigned8)
    parser it = withCollection "Block Word8" (fmap fromList . mapM parser . toList) it
            <|> withString "Block Word8" (first fromList . convertFromBase Base16) it
    -- builder blck = ITCollection $ builder <$> toList blck
    builder = Value.String . fromBytesUnsafe . convertToBase Base16
instance (Typeable a, Inspectable a) => Inspectable [a] where
    documentation _ = "collection of " <> documentation (Proxy @a)
    exportType _ = Type.Array (Type.UnsizedArray (exportType (Proxy @a)))
    parser = withCollection ("["<>show (typeRep (Proxy @a))<>"]") $ fmap fromList . mapM parser . toList
    builder l = Value.Array $ fromList $ builder <$> l
instance (HashAlgorithm hash, KnownNat (HashDigestSize hash)) => Inspectable (Digest hash) where
    documentation _ = "hexadecimal encoded bytes"
    exportType _ = Type.Array (Type.SizedArray Type.Unsigned8 size)
      where
        size = fromInteger $ natVal $ Proxy @(HashDigestSize hash)
    parser t = do
        blk <- parser t :: Either String (Block Word8)
        case digestFromByteString blk of
            Nothing -> reportError "invalid digest" t
            Just v  -> pure v
    builder t = builder (convert t :: Block Word8)
instance Inspectable Bytes where
    documentation _ = "hexadecimal encoded bytes"
    exportType _ = exportType (Proxy @(Block Word8))
    parser t = convert <$> (parser t :: Either String (Block Word8))
    builder t = builder (convert t :: Block Word8)
instance (HashAlgorithm hash, KnownNat (HashDigestSize hash)) => Inspectable (HMAC hash) where
    documentation _ = "hexadecimal encoded bytes"
    exportType _ = exportType (Proxy @(Digest hash))
    parser t = HMAC <$> parser t
    builder t = builder (convert t :: Block Word8)

-- ------------------------------------------------------------------------- --

instance Alternative (Either String) where
    empty = undefined
    (<|>) (Left _) r = r
    (<|>) l        _ = l

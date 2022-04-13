module CoreCTT where

import Data.List (intercalate,delete,deleteBy)
--import Data.Map (Map,toList,fromList,elems,keys)
import Data.Maybe (fromJust)
import Data.Set (Set(..))

import Ident
import Interval

{- Syntax (terms/values) -}

data Term
    = Var Ident (Maybe Value)
    | Universe
    | Abst Ident Term Term
    | App Term Term
    | Nat
    | Zero
    | Succ Term
    | Ind Term Term Term Term
    {- Cubical -}
    | I
    | I0 | I1 --TODO
    | Sys System
    | Partial Formula Term
    | Restr Formula Term Term
    {- Closure (values only) -}
    | Closure Ident Value Term (Ctx,DirEnv,Env) 
  deriving (Eq, Ord)

type Value = Term

newtype Program = Program [Toplevel]

data Toplevel = Definition Ident Term Term   -- Type-check and add to the context
              | Declaration Ident Term       -- Check type formation
              | Example Term                 -- Infer type and normalize 
  deriving (Eq, Ord)

isNumeral :: Term -> (Bool,Int)
isNumeral Zero     = (True,0)
isNumeral (Succ t) = (isNum,n + 1)
    where (isNum,n) = isNumeral t
isNumeral _ = (False,0)

isNeutral :: Value -> Bool
isNeutral v = case v of
    Var _ _     -> True
    App _ _     -> True
    Ind _ _ _ _ -> True
    otherwise    -> False

-- Generates a new name starting from 'x' (maybe too inefficient - TODO)
newVar :: [Ident] -> Ident -> Ident
newVar used x = if x `elem` used then newVar used (Ident $ show x ++ "'") else x

collectApps :: Term -> [Term] -> (Term,[Term])
collectApps t apps = case t of
    App t1 t2' -> collectApps t1 (t2' : apps)
    otherwise -> (t,apps)

collectAbsts :: Term -> [(Ident,Term)] -> (Term,[(Ident,Term)])
collectAbsts t absts = case t of
    Abst s t e -> collectAbsts e ((s,t) : absts)
    otherwise -> (t,absts)

class SyntacticObject a where
    containsVar :: Ident -> a -> Bool
    containsVar s x = s `elem` (vars x) --slower? TODO
    vars :: a -> [Ident]
    freeVars :: a -> [Ident]

instance SyntacticObject Ident where
    vars s = [s]
    freeVars s = [s]

instance SyntacticObject Term where
    vars t = case t of
        Var s _       -> [s]
        Universe      -> []
        Abst s t e    -> vars t ++ vars e
        App fun arg   -> vars fun ++ vars arg
        Nat           -> []
        Zero          -> []
        Succ t        -> vars t
        Ind ty b s n  -> vars ty ++ vars b ++ vars s ++ vars n
        I             -> []
        I0            -> []
        I1            -> []
        Sys sys       -> concatMap vars (keys sys) ++ concatMap vars (elems sys)
        Partial phi t -> vars phi ++ vars t
        Restr phi u t -> vars phi ++ vars u ++ vars t
    freeVars t = case t of
        Var s _       -> [s]
        Universe      -> []
        Abst s t e    -> freeVars t ++ filter (/= s) (freeVars e)
        App fun arg   -> freeVars fun ++ freeVars arg
        Nat           -> []
        Zero          -> []
        Succ t        -> freeVars t
        Ind ty b s n  -> freeVars ty ++ freeVars b ++ freeVars s ++ freeVars n
        I             -> []
        I0            -> []
        I1            -> []
        Sys sys       -> concatMap freeVars (keys sys) ++ concatMap freeVars (elems sys)
        Partial phi t -> freeVars phi ++ freeVars t
        Restr phi u t -> freeVars phi ++ freeVars u ++ freeVars t

instance SyntacticObject Formula where
    vars ff = case ff of
        FTrue -> []
        FFalse -> []
        Eq0 s' -> [s']
        Eq1 s' -> [s']
        Diag s1 s2 -> [s1,s2]
        ff1 :/\: ff2 -> vars ff1 ++ vars ff2
        ff1 :\/: ff2 -> vars ff1 ++ vars ff2
    freeVars ff = vars ff

checkTermShadowing :: [Ident] -> Term -> Bool
checkTermShadowing vars t = case t of
    Var s _             -> True
    Universe            -> True
    Abst (Ident "") t e -> checkTermShadowing vars t && checkTermShadowing vars e
    Abst s t e          -> not (s `elem` vars) &&
        checkTermShadowing (s : vars) t && checkTermShadowing (s : vars) e 
    App fun arg         -> checkTermShadowing vars fun && checkTermShadowing vars arg
    Nat                 -> True
    Zero                -> True
    Succ n              -> checkTermShadowing vars n
    Ind ty b s n        -> checkTermShadowing vars ty && checkTermShadowing vars b &&
        checkTermShadowing vars s && checkTermShadowing vars n
    I                   -> True
    I0                  -> True
    I1                  -> True
    Sys sys             -> all (checkTermShadowing vars) (elems sys)
    Partial phi t       -> checkTermShadowing vars t
    Restr phi u t       -> checkTermShadowing vars u && checkTermShadowing vars t


{- Printing functions are in 'Eval.hs' -}

{- Contexts -}

type ErrorString = String

{- Generic association lists utilities -}

--lookup :: (Eq a) => a -> [(a, b)] -> Maybe b --already defined in the Prelude

extend :: [(k,a)] -> k -> a -> [(k,a)]
extend al s v = (s,v) : al

keys :: [(k,a)] -> [k]
keys al = map fst al

elems :: [(k,a)] -> [a]
elems al = map snd al

mapElems :: (a -> b) -> [(k,a)] -> [(k,b)]
mapElems f al = map (\(s,v) -> (s,f v)) al

at :: (Eq k) => [(k,a)] -> k -> a
al `at` s = fromJust (lookup s al)

{- Evaluation enviroments -}

type Env = [(Ident,EnvEntry)]

data EnvEntry = Val Value
              | EDef Term Term
    deriving (Eq, Ord)

emptyEnv :: Env
emptyEnv = []

{- Contexts -}

type Ctx = [(Ident,CtxEntry)]

data CtxEntry = Decl Term      -- Type
              | Def Term Term  -- Type and definition
    deriving (Eq, Ord)

emptyCtx :: Ctx
emptyCtx = []

instance SyntacticObject CtxEntry where
    vars entry = case entry of
        Decl t     -> vars t
        Def ty def -> vars ty ++ vars def
    freeVars entry = case entry of
        Decl t     -> freeVars t
        Def ty def -> freeVars ty ++ freeVars def

lookupType :: Ctx -> Ident -> {-Either ErrorString-} Term
lookupType ctx s = do
    let mentry = lookup s ctx
    case mentry of
        Nothing -> error $ "[lookupType] got unknown identifier " ++ show s --Left $ "identifier '" ++ show s ++ "' not found in context"
        Just entry -> case entry of
            Decl ty     -> ty
            Def  ty def -> ty

ctxToEnv :: Ctx -> Env
ctxToEnv ctx = concatMap getEnvEntry (zip (keys ctx) (elems ctx))
    where
        getEnvEntry :: (Ident,CtxEntry) -> [(Ident,EnvEntry)]
        getEnvEntry (s,(Decl ty)) = []
        getEnvEntry (s,(Def ty val)) = [(s,(EDef ty val))]

getLockedCtx :: [Ident] -> Ctx -> Ctx
getLockedCtx idents ctx = foldr getLockedCtx' ctx idents
    where
        getLockedCtx' :: Ident -> Ctx -> Ctx
        getLockedCtx' s ((s',Def ty def) : ctx) =
            if s == s' then (s,Decl ty) : ctx
                       else (s',Def ty def) : getLockedCtx' s ctx
        getLockedCtx' s ((s',Decl ty) : ctx) =
            (s',Decl ty) : getLockedCtx' s ctx
        getLockedCtx' s ctx = ctx

removeFromCtx :: Ctx -> Ident -> Ctx
removeFromCtx ctx s = if s `elem` (keys ctx) then
        let fall = map fst $ filter (\(_,entry) -> s `elem` (freeVars entry) ) ctx
            ctx' = filter (\(s',_) -> s /= s') ctx
        in foldl removeFromCtx ctx' fall
    else
        ctx
{-
toEnv :: DirEnv -> Env
toEnv (zeros,ones,diags) = substs0 ++ substs1 ++ substsd
    where substs0 = map (\s -> (s,Val I0)) zeros
          substs1 = map (\s -> (s,Val I1)) ones
          substsd = concatMap (\part -> map (\s -> (s,Val $ Var (head part) (Just I))) part) diags
-}

toCtx :: DirEnv -> Ctx
toCtx (zeros,ones,diags) = substs0 ++ substs1 ++ substsd
    where substs0 = map (\s -> (s,Def I I0)) zeros
          substs1 = map (\s -> (s,Def I I1)) ones
          substsd = concatMap (\part -> map (\s -> (s,Def I $ Var (head part) (Just I))) part) diags


substDirs :: Formula -> DirEnv -> Formula
substDirs ff dirs = multipleSubst ff (toSubsts dirs)

{- Cubical -}

type System = [(Formula,Term)]


--Orton pitts


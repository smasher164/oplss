{- pi-forall -}

{-# HLINT ignore "Use forM_" #-}

-- | The main routines for type-checking
module TypeCheck (tcModules, inferType, checkType) where

import Control.Monad.Except
import Data.Maybe (catMaybes)
import Debug.Trace
import Environment (D (..), TcMonad)
import Environment qualified as Env
import Equal qualified
import PrettyPrint (Disp (disp), debug, pp)
import Syntax
import Text.PrettyPrint.HughesPJ (render, ($$))
import Unbound.Generics.LocallyNameless qualified as Unbound

---------------------------------------------------------------------

-- | Infer/synthesize the type of a term
inferType :: Term -> TcMonad Type
inferType a = case a of
  -- i-var
  (Var x) -> do
    decl <- Env.lookupTy x
    return (declType decl)

  -- i-type
  TyType -> return TyType
  -- i-pi
  (TyPi tyA bnd) -> do
    (x, tyB) <- unbind bnd
    tcType tyA
    Env.extendCtx (mkDecl x tyA) (tcType tyB)
    return TyType

  -- i-app
  (App a b) -> do
    ty1 <- inferType a
    let ty1' = strip ty1
    case ty1' of
      (TyPi tyA bnd) -> do
        checkType b tyA
        return (instantiate bnd b)
      _ -> Env.err [DS "Expected a function type but found ", DD ty1]

  -- i-ann
  (Ann a tyA) -> do
    tcType tyA
    checkType a tyA
    return tyA

  -- Practicalities
  -- remember the current position in the type checking monad
  (Pos p a) ->
    Env.extendSourceLocation p a $ inferType a
  -- Extensions to the core language
  -- i-unit
  TyUnit -> return TyType
  LitUnit -> return TyUnit
  -- i-bool
  TyBool -> return TyType
  -- i-true/false
  (LitBool _) -> return TyBool
  -- i-if
  (If a b1 b2) -> do
    checkType a TyBool
    b1t <- inferType b1
    checkType b2 b1t
    return b1t
    
  -- i-sigma
  (TySigma tyA bnd) -> Env.err [DS "unimplemented"]
  -- cannot synthesize the type of the term
  _ ->
    Env.err [DS "Must have a type annotation for", DD a]

-------------------------------------------------------------------------

-- | Make sure that the term is a "type" (i.e. that it has type 'Type')
tcType :: Term -> TcMonad ()
tcType tm = checkType tm TyType

-------------------------------------------------------------------------

-- | Check that the given term has the expected type
checkType :: Term -> Type -> TcMonad ()
checkType tm ty = do
  let ty' = strip ty -- ignore source positions/annotations
  case tm of
    -- c-lam: check the type of a function
    (Lam bnd) -> case ty' of
      (TyPi tyA bnd2) -> do
        -- unbind the variables in the lambda expression and pi type
        (x, body, tyB) <- unbind2 bnd bnd2

        -- check the type of the body of the lambda expression
        Env.extendCtx (mkDecl x tyA) (checkType body tyB)
      _ -> Env.err [DS "Lambda expression should have a function type, not", DD ty']
    -- Practicalities
    (Pos p a) ->
      Env.extendSourceLocation p a $ checkType a ty'
    TrustMe -> return ()
    PrintMe -> do
      gamma <- Env.getLocalCtx
      Env.warn
        [ DS "Unmet obligation.\nContext:",
          DD gamma,
          DS "\nGoal:",
          DD ty'
        ]

    -- Extensions to the core language
    -- c-if
    (If a b1 b2) -> do
      checkType a TyBool
      checkType b1 ty
      checkType b2 ty
    -- c-prod
    (Prod a b) -> Env.err [DS "unimplemented"]
    -- c-letpair
    (LetPair p bnd) -> Env.err [DS "unimplemented"]
    -- c-let
    (Let a bnd) -> Env.err [DS "unimplemented"]
    -- c-infer
    _ -> do
      tyA <- inferType tm
      unless (aeq tyA ty') $ Env.err [DS "Types don't match", DD tyA, DS "and", DD ty']

--------------------------------------------------------
-- Using the typechecker for decls and modules and stuff
--------------------------------------------------------

-- | Typecheck a collection of modules. Assumes that each module
-- appears after its dependencies. Returns the same list of modules
-- with each definition typechecked
tcModules :: [Module] -> TcMonad [Module]
tcModules = foldM tcM []
  where
    -- Check module m against modules in defs, then add m to the list.
    defs `tcM` m = do
      -- "M" is for "Module" not "monad"
      let name = moduleName m
      liftIO $ putStrLn $ "Checking module " ++ show name
      m' <- defs `tcModule` m
      return $ defs ++ [m']

-- | Typecheck an entire module.
tcModule ::
  -- | List of already checked modules (including their entries).
  [Module] ->
  -- | Module to check.
  Module ->
  -- | The same module with all entries checked and elaborated.
  TcMonad Module
tcModule defs m' = do
  checkedEntries <-
    Env.extendCtxMods importedModules $
      foldr
        tcE
        (return [])
        (moduleEntries m')
  return $ m' {moduleEntries = checkedEntries}
  where
    d `tcE` m = do
      -- Extend the Env per the current Entry before checking
      -- subsequent entries.
      x <- tcEntry d
      case x of
        AddHint hint -> Env.extendHints hint m
        -- Add decls to the entries to be returned
        AddCtx decls -> (decls ++) <$> Env.extendCtxsGlobal decls m
    -- Get all of the defs from imported modules (this is the env to check current module in)
    importedModules = filter (\x -> ModuleImport (moduleName x) `elem` moduleImports m') defs

-- | The Env-delta returned when type-checking a top-level Entry.
data HintOrCtx
  = AddHint TypeDecl
  | AddCtx [Entry]

-- | Check each sort of declaration in a module
tcEntry :: Entry -> TcMonad HintOrCtx
tcEntry (Def n term) = do
  oldDef <- Env.lookupDef n
  maybe tc die oldDef
  where
    tc = do
      lkup <- Env.lookupHint n
      case lkup of
        Nothing -> do
          ty <- inferType term
          return $ AddCtx [Decl (TypeDecl n ty), Def n term]
        Just decl ->
          let handler (Env.Err ps msg) = throwError $ Env.Err ps (msg $$ msg')
              msg' =
                disp
                  [ DS "When checking the term",
                    DD term,
                    DS "against the type",
                    DD decl
                  ]
           in do
                Env.extendCtx (Decl decl) $ checkType term (declType decl) `catchError` handler
                return $ AddCtx [Decl decl, Def n term]
    die term' =
      Env.extendSourceLocation (unPosFlaky term) term $
        Env.err
          [ DS "Multiple definitions of",
            DD n,
            DS "Previous definition was",
            DD term'
          ]
tcEntry (Decl decl) = do
  duplicateTypeBindingCheck decl
  tcType (declType decl)
  return $ AddHint decl

-- | Make sure that we don't have the same name twice in the
-- environment. (We don't rename top-level module definitions.)
duplicateTypeBindingCheck :: TypeDecl -> TcMonad ()
duplicateTypeBindingCheck decl = do
  -- Look for existing type bindings ...
  let n = declName decl
  l <- Env.lookupTyMaybe n
  l' <- Env.lookupHint n
  -- ... we don't care which, if either are Just.
  case catMaybes [l, l'] of
    [] -> return ()
    -- We already have a type in the environment so fail.
    decl' : _ ->
      let p = unPosFlaky $ declType decl
          msg =
            [ DS "Duplicate type declaration",
              DD decl,
              DS "Previous was",
              DD decl'
            ]
       in Env.extendSourceLocation p decl $ Env.err msg

{- pi-forall language -}

-- | Compare two terms for equality
module Equal (whnf, equate, unify
              {- SOLN DATA -},ensureTCon{- STUBWITH -} ) where

import Syntax
import Environment ( D(DS, DD), TcMonad )
import qualified Environment as Env
import qualified Unbound.Generics.LocallyNameless as Unbound

import Control.Monad.Except (unless, catchError, zipWithM, zipWithM_)

-- | compare two expressions for equality
-- first check if they are alpha equivalent then
-- if not, weak-head normalize and compare
-- throw an error if they cannot be matched up
equate :: Term -> Term -> TcMonad ()
equate t1 t2 | Unbound.aeq t1 t2 = return () 
equate t1 t2 = do
  n1 <- whnf t1  
  n2 <- whnf t2
  case (n1, n2) of 
    (TyType, TyType) -> return ()
    (Var x,  Var y) | x == y -> return ()
    (Lam {- SOLN EP -} ep1 {- STUBWITH -}bnd1, Lam {- SOLN EP -} ep2 {- STUBWITH -}bnd2) -> do
      (_, b1, b2) <- unbind2 bnd1 bnd2
{- SOLN EP -} 
      unless (ep1 == ep2) $
          tyErr n1 n2 {- STUBWITH -}
      equate b1 b2
    (App a1 a2, App b1 b2) ->
      equate a1 b1 >> {- SOLN EP -} equateArg{- STUBWITH equate -} a2 b2
    (TyPi {- SOLN EP -} ep1 {- STUBWITH -}tyA1 bnd1, TyPi {- SOLN EP -} ep2 {- STUBWITH -}tyA2 bnd2) -> do 
      (_, tyB1, tyB2) <- unbind2 bnd1 bnd2 
{- SOLN EP -} 
      unless (ep1 == ep2) $
          tyErr n1 n2 {- STUBWITH -}
      equate tyA1 tyA2                                             
      equate tyB1 tyB2

    (TrustMe, TrustMe) ->  return ()
    (PrintMe, PrintMe) ->  return ()
    
    (TyUnit, TyUnit)   -> return ()
    (LitUnit, LitUnit) -> return ()
    
    (TyBool, TyBool)   -> return ()
    
    (LitBool b1, LitBool b2) | b1 == b2 -> return ()
    
    (If a1 b1 c1, If a2 b2 c2) -> do
      equate a1 a2
      equate b1 b2 
      equate c1 c2
      
    (Let rhs1 bnd1, Let rhs2 bnd2) -> do
      (x, body1, body2) <- unbind2 bnd1 bnd2
      equate rhs1 rhs2
      equate body1 body2
            
    (TySigma tyA1 bnd1, TySigma tyA2 bnd2) -> do 
      (x, tyB1, tyB2) <- unbind2 bnd1 bnd2
      equate tyA1 tyA2                                             
      equate tyB1 tyB2

    (Prod a1 b1, Prod a2 b2) -> do
      equate a1 a2
      equate b1 b2
      
    (LetPair s1 bnd1, LetPair s2 bnd2) -> do  
      equate s1 s2
      ((x,y), body1, _, body2) <- Unbound.unbind2Plus bnd1 bnd2
      equate body1 body2
{- SOLN EQUAL -}      
    (TyEq a b, TyEq c d) -> do
      equate a c 
      equate b d      
    
    (Refl,  Refl) -> return ()
    
    (Subst at1 pf1, Subst at2 pf2) -> do
      equate at1 at2
      equate pf1 pf2
        
    (Contra a1, Contra a2) -> 
      equate a1 a2
{- STUBWITH -}      
{- SOLN DATA -}      
    (TyCon c1 ts1, TyCon c2 ts2) | c1 == c2 -> 
      zipWithM_ equateArgs [ts1] [ts2]
    (DataCon d1 a1, DataCon d2 a2) | d1 == d2 -> do
      equateArgs a1 a2
    (Case s1 brs1, Case s2 brs2) 
      | length brs1 == length brs2 -> do
      equate s1 s2
      -- require branches to be in the same order
      -- on both expressions
      let matchBr (Match bnd1) (Match bnd2) = do
            mpb <- Unbound.unbind2 bnd1 bnd2
            case mpb of 
              Just (p1, a1, p2, a2) | p1 == p2 -> do
                equate a1 a2
              _ -> Env.err [DS "Cannot match branches in",
                              DD n1, DS "and", DD n2]
      zipWithM_ matchBr brs1 brs2       
{- STUBWITH -}
    (_,_) -> tyErr n1 n2
 where tyErr n1 n2 = do 
          gamma <- Env.getLocalCtx
          Env.err [DS "Expected", DD n2,
               DS "but found", DD n1,
               DS "in context:", DD gamma]
       

{- SOLN EP -}
-- | Match up args
equateArgs :: [Arg] -> [Arg] -> TcMonad ()    
equateArgs (a1:t1s) (a2:t2s) = do
  equateArg a1 a2
  equateArgs t1s t2s
equateArgs [] [] = return ()
equateArgs a1 a2 = do 
          gamma <- Env.getLocalCtx
          Env.err [DS "Expected", DD (length a2),
                   DS "but found", DD (length a1),
                   DS "in context:", DD gamma]

-- | Ignore irrelevant arguments when comparing 
equateArg :: Arg -> Arg -> TcMonad ()
equateArg (Arg Rel t1) (Arg Rel t2) = equate t1 t2
equateArg (Arg Irr t1) (Arg Irr t2) = return ()
equateArg a1 a2 =  
  Env.err [DS "Arg stage mismatch",
              DS "Expected " , DD a2, 
              DS "Found ", DD a1] 
{- STUBWITH -}

-------------------------------------------------------
    
{- SOLN DATA -}

-- | Ensure that the given type 'ty' is some tycon applied to 
--  params (or could be normalized to be such)
-- Throws an error if this is not the case 
ensureTCon :: Term -> TcMonad (TyConName, [Arg])
ensureTCon aty = do
  nf <- whnf aty
  case nf of 
    TyCon n params -> return (n, params)    
    _ -> Env.err [DS "Expected a data type but found", DD nf]
{- STUBWITH -}
    

-------------------------------------------------------
-- | Convert a term to its weak-head normal form.             
whnf :: Term -> TcMonad Term  
whnf (Var x) = do      
  maybeDef <- Env.lookupDef x
  case maybeDef of 
    (Just d) -> whnf d 
    _ -> return (Var x)
        
whnf (App t1 t2) = do
  nf <- whnf t1 
  case nf of 
    (Lam {- SOLN EP -} ep {- STUBWITH -} bnd) -> do
      whnf (instantiate bnd {- SOLN EP -} (unArg t2) {- STUBWITH t2 -})
    _ -> do
      return (App nf t2)
      
whnf (If t1 t2 t3) = do
  nf <- whnf t1
  case nf of 
    (LitBool bo) -> if bo then whnf t2 else whnf t3
    _ -> return (If nf t2 t3)

whnf (LetPair a bnd) = do
  nf <- whnf a 
  case nf of 
    Prod b1 c -> do
      whnf (Unbound.instantiate bnd [b1, c])
    _ -> return (LetPair nf bnd)

-- ignore/remove type annotations and source positions when normalizing  
whnf (Ann tm _) = whnf tm
whnf (Pos _ tm) = whnf tm
 
{- SOLN HW -}
whnf (Let rhs bnd)  = do
  whnf (instantiate bnd rhs){- STUBWITH -}  
{- SOLN EQUAL -}  
whnf (Subst tm pf) = do
  pf' <- whnf pf
  case pf' of 
    Refl -> whnf tm
    _ -> return (Subst tm pf'){- STUBWITH -}    
{- SOLN DATA -}      
whnf (Case scrut mtchs) = do
  nf <- whnf scrut        
  case nf of 
    (DataCon d args) -> f mtchs where
      f (Match bnd : alts) = (do
          (pat, br) <- Unbound.unbind bnd
          ss <- patternMatches (Arg Rel nf) pat 
          whnf (Unbound.substs ss br)) 
            `catchError` \ _ -> f alts
      f [] = Env.err $ [DS "Internal error: couldn't find a matching",
                    DS "branch for", DD nf, DS "in"] ++ map DD mtchs
    _ -> return (Case nf mtchs){- STUBWITH -}            
-- all other terms are already in WHNF
-- don't do anything special for them
whnf tm = return tm

-- | 'Unify' the two terms, producing a list of definitions that 
-- must hold for the terms to be equal
-- If the terms are already equal, succeed with an empty list
-- If there is an obvious mismatch, fail with an error
-- If either term is "ambiguous" (i.e. neutral), give up and 
-- succeed with an empty list
unify :: [TName] -> Term -> Term -> TcMonad [Entry]
unify ns tx ty = do
  txnf <- whnf tx
  tynf <- whnf ty
  if Unbound.aeq txnf tynf
    then return []
    else case (txnf, tynf) of
      (Var x, Var y) | x == y -> return []
      (Var y, yty) | y `notElem` ns -> return [Def y yty]
      (yty, Var y) | y `notElem` ns -> return [Def y yty]
      (Prod a1 a2, Prod b1 b2) -> {- SOLN EP -} unifyArgs [Arg Rel a1, Arg Rel a2] [Arg Rel b1, Arg Rel b2] {- STUBWITH (++) <$> unify ns a1 b1 <*> unify ns a2 b2 -} 
      
{- SOLN EQUAL -}
      (TyEq a1 a2, TyEq b1 b2) -> (++) <$> unify ns a1 b1 <*> unify ns a2 b2 {- STUBWITH -}
{- SOLN DATA -}
      (TyCon s1 tms1, TyCon s2 tms2)
        | s1 == s2 -> unifyArgs tms1 tms2
      (DataCon s1 a1s, DataCon s2 a2s)
        | s1 == s2 -> unifyArgs a1s a2s {- STUBWITH -}
      (Lam {- SOLN EP -} ep1 {- STUBWITH -} bnd1, Lam {- SOLN EP -} ep2 {- STUBWITH -} bnd2) -> do
        (x, b1, b2) <- unbind2 bnd1 bnd2
{- SOLN EP -}
        unless (ep1 == ep2) $ do
          Env.err [DS "Cannot equate", DD txnf, DS "and", DD tynf] {- STUBWITH -}
        unify (x:ns) b1 b2
      (TyPi {- SOLN EP -} ep1 {- STUBWITH -} tyA1 bnd1, TyPi {- SOLN EP -} ep2 {- STUBWITH -} tyA2 bnd2) -> do
        (x, tyB1, tyB2) <- unbind2 bnd1 bnd2 
{- SOLN EP -}
        unless (ep1 == ep2) $ do
          Env.err [DS "Cannot equate", DD txnf, DS "and", DD tynf] {- STUBWITH -}
        ds1 <- unify ns tyA1 tyA2
        ds2 <- unify (x:ns) tyB1 tyB2
        return (ds1 ++ ds2)
      _ ->
        if amb txnf || amb tynf
          then return []
          else Env.err [DS "Cannot equate", DD txnf, DS "and", DD tynf] 
{- SOLN EP -}
  where
    unifyArgs (Arg _ t1 : a1s) (Arg _ t2 : a2s) = do
      ds <- unify ns t1 t2
      ds' <- unifyArgs a1s a2s
      return $ ds ++ ds'
    unifyArgs [] [] = return []
    unifyArgs _ _ = Env.err [DS "internal error (unify)"] {- STUBWITH -}


-- | Is a term "ambiguous" when it comes to unification?
-- In general, elimination forms are ambiguous because there are multiple 
-- solutions.
amb :: Term -> Bool
amb (App t1 t2) = True
amb If {} = True
amb (LetPair _ _) = True 
{- SOLN DATA -}
amb (Case _ _) = True  {- STUBWITH -} 
{- SOLN EQUAL -}
amb (Subst _ _) = True {- STUBWITH -}
amb _ = False

{- SOLN DATA -}
-- | Determine whether the pattern matches the argument
-- If so return the appropriate substitution
-- otherwise throws an error
patternMatches :: Arg -> Pattern -> TcMonad [(TName, Term)]
patternMatches (Arg _ t) (PatVar x) = return [(x, t)]
patternMatches (Arg Rel t) pat = do
  nf <- whnf t
  case (nf, pat) of 
    (DataCon d [], PatCon d' pats)   | d == d' -> return []
    (DataCon d args, PatCon d' pats) | d == d' -> 
       concat <$> zipWithM patternMatches args (map fst pats)
    _ -> Env.err [DS "arg", DD nf, DS "doesn't match pattern", DD pat]
patternMatches (Arg Irr _) pat = do
  Env.err [DS "Cannot match against irrelevant args"]

{- STUBWITH -}


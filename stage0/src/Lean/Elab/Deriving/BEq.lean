/-
Copyright (c) 2020 Microsoft Corporation. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Leonardo de Moura
-/
import Lean.Meta.Transform
import Lean.Elab.Deriving.Basic
import Lean.Elab.Deriving.Util

namespace Lean.Elab.Deriving.BEq

open Meta

structure Header where
  binders     : Array Syntax
  argNames    : Array Name
  target1Name : Name
  target2Name : Name

def mkHeader (ctx : Context) (indVal : InductiveVal) : TermElabM Header := do
  let argNames      ← mkInductArgNames indVal
  let binders       ← mkImplicitBinders argNames
  let targetType    ← mkInductiveApp indVal argNames
  let target1Name   ← mkFreshUserName `x
  let target2Name   ← mkFreshUserName `y
  let binders      := binders ++ (← mkInstImplicitBinders `BEq indVal argNames)
  let target1Binder ← `(explicitBinderF| ($(mkIdent target1Name) : $targetType))
  let target2Binder ← `(explicitBinderF| ($(mkIdent target2Name) : $targetType))
  let binders      := binders ++ #[target1Binder, target2Binder]
  return {
    binders     := binders
    argNames    := argNames
    target1Name := target1Name
    target2Name := target2Name
  }

def mkMatch (ctx : Context) (header : Header) (indVal : InductiveVal) (auxFunName : Name) (argNames : Array Name) : TermElabM Syntax := do
  let discrs ← mkDiscrs
  let alts ← mkAlts
  `(match $[$discrs],* with | $[$alts:matchAlt]|*)
where
  mkDiscr (varName : Name) : TermElabM Syntax :=
    `(Parser.Term.matchDiscr| $(mkIdent varName):term)

  mkDiscrs : TermElabM (Array Syntax) := do
    let mut discrs := #[]
    -- add indices
    for argName in argNames[indVal.nparams:] do
      discrs := discrs.push (← mkDiscr argName)
    return discrs ++ #[← mkDiscr header.target1Name, ← mkDiscr header.target2Name]

  mkElseAlt : TermElabM Syntax := do
    let mut patterns := #[]
    -- add `_` pattern for indices
    for i in [:indVal.nindices] do
      patterns := patterns.push (← `(_))
    patterns := patterns.push (← `(_))
    patterns := patterns.push (← `(_))
    let altRhs ← `(false)
    `(matchAltExpr| $[$patterns:term],* => $altRhs:term)

  mkAlts : TermElabM (Array Syntax) := do
    let mut alts := #[]
    for ctorName in indVal.ctors do
      let ctorInfo ← getConstInfoCtor ctorName
      let alt ← forallTelescopeReducing ctorInfo.type fun xs type => do
        let type ← Core.betaReduce type -- we 'beta-reduce' to eliminate "artificial" dependencies
        let mut patterns := #[]
        -- add `_` pattern for indices
        for i in [:indVal.nindices] do
          patterns := patterns.push (← `(_))
        let mut ctorArgs1 := #[]
        let mut ctorArgs2 := #[]
        let mut rhs ← `(true)
        -- add `_` for inductive parameters, they are inaccessible
        for i in [:indVal.nparams] do
          ctorArgs1 := ctorArgs1.push (← `(_))
          ctorArgs2 := ctorArgs2.push (← `(_))
        for i in [:ctorInfo.nfields] do
          let x := xs[indVal.nparams + i]
          if type.containsFVar x.fvarId! then
            -- If resulting type depends on this field, we don't need to compare
            ctorArgs1 := ctorArgs1.push (← `(_))
            ctorArgs2 := ctorArgs2.push (← `(_))
          else
            let a := mkIdent (← mkFreshUserName `a)
            let b := mkIdent (← mkFreshUserName `b)
            ctorArgs1 := ctorArgs1.push a
            ctorArgs2 := ctorArgs2.push b
            if (← inferType x).isAppOf indVal.name then
              rhs ← `($rhs && $(mkIdent auxFunName):ident $a:ident $b:ident)
            else
              rhs ← `($rhs && $a:ident == $b:ident)
        patterns := patterns.push (← `(@$(mkIdent ctorName):ident $ctorArgs1:term*))
        patterns := patterns.push (← `(@$(mkIdent ctorName):ident $ctorArgs2:term*))
        `(matchAltExpr| $[$patterns:term],* => $rhs:term)
      alts := alts.push alt
    alts := alts.push (← mkElseAlt)
    return alts

def mkAuxFunction (ctx : Context) (i : Nat) : TermElabM Syntax := do
  let auxFunName ← ctx.auxFunNames[i]
  let indVal     ← ctx.typeInfos[i]
  let header     ← mkHeader ctx indVal
  let mut body   ← mkMatch ctx header indVal auxFunName header.argNames
  if ctx.usePartial then
    let letDecls ← mkLocalInstanceLetDecls ctx `BEq header.argNames
    body ← mkLet letDecls body
  let binders    := header.binders
  if ctx.usePartial then
    `(private partial def $(mkIdent auxFunName):ident $binders:explicitBinder* : Bool := $body:term)
  else
    `(private def $(mkIdent auxFunName):ident $binders:explicitBinder* : Bool := $body:term)

def mkMutualBlock (ctx : Context) : TermElabM Syntax := do
  let mut auxDefs := #[]
  for i in [:ctx.typeInfos.size] do
    auxDefs := auxDefs.push (← mkAuxFunction ctx i)
  `(mutual
     set_option match.ignoreUnusedAlts true
     $auxDefs:command*
    end)

private def mkBEqInstanceCmds (declNames : Array Name) : TermElabM (Array Syntax) := do
  let ctx ← mkContext declNames[0]
  let cmds := #[← mkMutualBlock ctx] ++ (← mkInstanceCmds ctx `BEq declNames)
  trace[Elab.Deriving.beq]! "\n{cmds}"
  return cmds

open Command

def mkBEqInstanceHandler (declNames : Array Name) : CommandElabM Bool := do
  if (← declNames.allM isInductive) && declNames.size > 0 then
    let cmds ← liftTermElabM none <| mkBEqInstanceCmds declNames
    cmds.forM elabCommand
    return true
  else
    return false

builtin_initialize
  registerBuiltinDerivingHandler `BEq mkBEqInstanceHandler
  registerTraceClass `Elab.Deriving.beq

end Lean.Elab.Deriving.BEq

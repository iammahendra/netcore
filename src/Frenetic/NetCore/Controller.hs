--------------------------------------------------------------------------------
-- The Frenetic Project                                                       --
-- frenetic@frenetic-lang.org                                                 --
--------------------------------------------------------------------------------
-- Licensed to the Frenetic Project by one or more contributors. See the      --
-- NOTICE file distributed with this work for additional information          --
-- regarding copyright and ownership. The Frenetic Project licenses this      --
-- file to you under the following license.                                   --
--                                                                            --
-- Redistribution and use in source and binary forms, with or without         --
-- modification, are permitted provided the following conditions are met:     --
-- * Redistributions of source code must retain the above copyright           --
--   notice, this list of conditions and the following disclaimer.            --
-- * Redistributions of binaries must reproduce the above copyright           --
--   notice, this list of conditions and the following disclaimer in          --
--   the documentation or other materials provided with the distribution.     --
-- * The names of the copyright holds and contributors may not be used to     --
--   endorse or promote products derived from this work without specific      --
--   prior written permission.                                                --
--                                                                            --
-- Unless required by applicable law or agreed to in writing, software        --
-- distributed under the License is distributed on an "AS IS" BASIS, WITHOUT  --
-- WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the   --
-- LICENSE file distributed with this work for specific language governing    --
-- permissions and limitations under the License.                             --
--------------------------------------------------------------------------------
-- /src/Frenetic/NetCore/Controller.hs                                        --
--                                                                            --
-- $Id$ --
--------------------------------------------------------------------------------

{-# LANGUAGE TemplateHaskell #-}


module Frenetic.NetCore.Controller where

import Frenetic.NetCore.Action
import Control.Monad.State.Lazy

import Frenetic.NetCore.API
--import Frenetic.NetCore.Compiler

type Hook = ControllerM ()

-- FIX this should maybe be an interval of rules? rule ids?
{-| Identifies a partial policy -}
type PolicyID = Int

{-| Identifies a NetCore controller -}
type ControllerID = Int

{-| Controller state -}
data Controller = Controller {
  ctrlPacketIn :: [Hook],
  ctrlSwitchJoin :: [Hook],
  ctrlSwitchLeave :: [Hook]
  }
                       
{-| Controller monad -}
newtype ControllerM a = ControllerM (StateT Controller IO a) 

{-| Make a controller -}
mkController :: IO ControllerID 
mkController = undefined -- runStateT

{-| Send a sequence of commands to a controller -}
withController :: ControllerID -> ControllerM () -> IO ()
withController = undefined

{-| Install a new policy on the controller -}
installPolicy :: Policy -> ControllerM ()
installPolicy = undefined

{-| Install part of a policy on the controller: this policy should be an expansion of the base installed policy. -}
installPartialPolicy :: Policy -> ControllerM PolicyID
installPartialPolicy = undefined

{-| Remove part of a policy -}
deletePartialPolicy :: PolicyID -> ControllerM ()
deletePartialPolicy = undefined

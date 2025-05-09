// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.19;

import {IWormholeRelayer} from "../../../interfaces/relayer/IWormholeRelayerTyped.sol";

import {WormholeRelayerGovernance} from "./WormholeRelayerGovernance.sol";
import {WormholeRelayerSend} from "./WormholeRelayerSend.sol";
import {WormholeRelayerDelivery} from "./WormholeRelayerDelivery.sol";
import {WormholeRelayerBase} from "./WormholeRelayerBase.sol";
import {WormholeRelayerStorage} from "./WormholeRelayerStorage.sol";

//WormholeRelayerGovernance inherits from ERC1967Upgrade, i.e. this is a proxy contract!
contract WormholeRelayer is
    WormholeRelayerGovernance,
    WormholeRelayerSend,
    WormholeRelayerDelivery,
    IWormholeRelayer
{
    //the only normal storage variable - everything else uses slot pattern
    //no point doing it for this one since it is entirely one-off and of no interest to the rest
    //  of the contract and it also can't accidentally be moved because we are at the bottom of
    //  the inheritance hierarchy here
    bool private initialized;

    constructor(
        address wormhole,
        address priceOracle,
        bytes32 solAssetId,
        bytes32 wethAssetId
    ) WormholeRelayerBase(wormhole, priceOracle, solAssetId, wethAssetId) {}

    //needs to be called upon construction of the EC1967 proxy
    function initialize(address owner) public {
        assert(!initialized);
        WormholeRelayerStorage.getOwnerState().owner = owner;
        initialized = true;
    }
}

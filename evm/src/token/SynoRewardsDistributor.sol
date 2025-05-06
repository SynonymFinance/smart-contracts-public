// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { RewardsDistributor } from  "./RewardsDistributor.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@solmate/utils/MerkleProofLib.sol";
import {IERC20} from "@balancer-labs/v2-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";
import {vlSYNO} from "./vlSyno.sol";
import {IVault, IWETH} from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SynoBalancerPoolHelper, IBalancerPoolToken, IBalancerQueries, _asIAsset, WeightedPoolUserData} from "./SynoBalancerPoolHelper.sol";

/**
 * @title SynoRewardsDistributor
 * @dev Contract for claiming rewards via merkle proofs. One deployment per reward token.
 */
contract SynoRewardsDistributor is RewardsDistributor {
  using SynoBalancerPoolHelper for IBalancerPoolToken;

  vlSYNO public vlSyno;
  address public treasury;

  error InsufficientETHAmount();
  error ETHTransferFailed();
  error InvalidArguments();
  error IncorrectETHAmountSent();
  error LockPeriodNotSupported();

  function initialize(address _token, address _vlSyno, address _treasury) public initializer {
    RewardsDistributor.__RewardsDistributor_init(_token);
    OwnableUpgradeable.__Ownable_init(msg.sender);

    vlSyno = vlSYNO(_vlSyno);
    treasury = _treasury;
  }

  function _calculateSynoBonusAmount(vlSYNO.LockPeriod lockPeriod, uint256 amount) internal pure returns(uint256) {
    if (lockPeriod == vlSYNO.LockPeriod.ONE_MONTH) {
      return 0;
    }

    if (lockPeriod == vlSYNO.LockPeriod.THREE_MONTHS) {
      return amount * 25 / 100;
    }

    if (lockPeriod == vlSYNO.LockPeriod.SIX_MONTHS) {
      return amount * 45 / 100;
    }

    if (lockPeriod == vlSYNO.LockPeriod.TWELVE_MONTHS) {
      return amount * 75 / 100;
    }

    revert LockPeriodNotSupported();
  }

  function _calculateBaseAmount(uint256 amount) internal pure returns(uint256) {
    return amount / 4; // 25%
  }

  function getRequiredETHAmount(uint256 synoAmount) public view returns(uint256) {
    return IBalancerPoolToken(vlSyno.poolToken())._calculateRequiredETHAmount(synoAmount);
  }

  /**
       * @dev Returns the amount of ETH that needs to be provided.
     * @param amount of syno to be claimed from the merkle tree.
     * @param lockPeriod for vlSYNO lock.
     */
  function getSynoAndRequiredETHAmount(uint256 amount, vlSYNO.LockPeriod lockPeriod) public view returns(uint256, uint256) {
    uint256 synoAmount = _calculateBaseAmount(amount) + _calculateSynoBonusAmount(lockPeriod, amount);

    uint256 requiredETHAmount = getRequiredETHAmount(synoAmount);

    return (synoAmount, requiredETHAmount);
  }

  /**
       * @dev Claim rewards without bonus.
     * @param inputs containing the merkle tree leaf details.
     */
  function claim(ClaimInput[] calldata inputs) override external {
    address recipient = msg.sender;
    uint256 totalAmount = 0;

    for(uint256 i = 0;i < inputs.length; i++) {
      ClaimInput calldata input = inputs[i];

      _verifyMerkleProof(input, recipient);

      isClaimed[input.epoch][recipient] = true;

      totalAmount += input.amount;

      emit Claimed(input.epoch, recipient, _calculateBaseAmount(input.amount));
    }

    uint256 baseOfTotal = _calculateBaseAmount(totalAmount);
    IERC20(token).transfer(recipient, baseOfTotal);

    // Send remainder SYNO to treasury
    IERC20(token).transfer(treasury, totalAmount - baseOfTotal);
  }

  /**
       * @dev Claim rewards with bonus, need 20% ETH value of the claimed SYNO.
     * @param inputs array containing the merkle tree leaf details.
     * @param ethAmounts array containing eth amounts to lock each reward. Sum should be equal to msg.value
     * @param lockPeriods array of vlSyno Lock periods.
     */
  function claim(ClaimInput[] calldata inputs, uint256[] calldata ethAmounts, vlSYNO.LockPeriod[] calldata lockPeriods) external payable {
    uint256 remainingETHAmount = msg.value;

    if(inputs.length != lockPeriods.length || inputs.length != ethAmounts.length) {
      revert InvalidArguments();
    }

    IBalancerPoolToken poolToken = IBalancerPoolToken(vlSyno.poolToken());
    for(uint256 i = 0;i < inputs.length;i++) {
      ClaimInput calldata input = inputs[i];
      vlSYNO.LockPeriod lockPeriod = lockPeriods[i];
      uint256 ethAmount = ethAmounts[i];

      _verifyMerkleProof(input, msg.sender);

      isClaimed[input.epoch][msg.sender] = true;

      // Calculate required amount of ETH
      (uint256 synoAmount, uint256 requiredETHAmount) = getSynoAndRequiredETHAmount(input.amount, lockPeriod);

      if(remainingETHAmount < ethAmount) {
        revert InsufficientETHAmount();
      }

      // Scale down syno amount if eth amount was specified to low. If it is more than required just make it max bonus.
      if(ethAmount < requiredETHAmount) {
        synoAmount = synoAmount * ethAmount / requiredETHAmount;

        uint256 baseSynoAmount = _calculateBaseAmount(input.amount);
        // If less than min bonus, just use the base amount
        if(synoAmount < baseSynoAmount) {
          synoAmount = baseSynoAmount;
        }
      }

      remainingETHAmount -= ethAmount;

      // Join Pool
      uint256 receivedBalancerLPTokens = poolToken._joinBalancerPool(synoAmount, ethAmount);

      // Stake LP Tokens in VLSyno Pool
      poolToken.approve(address(vlSyno), receivedBalancerLPTokens);
      vlSyno.stake(receivedBalancerLPTokens, lockPeriod, msg.sender);

      // Send remainder SYNO to treasury
      if(input.amount - synoAmount > 0) {
        IERC20(token).transfer(treasury, input.amount - synoAmount);
      }

      emit Claimed(input.epoch, msg.sender, synoAmount);
    }

    // Ensure msg.value === sum of ethAmounts
    if(remainingETHAmount != 0) {
      revert IncorrectETHAmountSent();
    }
  }
}

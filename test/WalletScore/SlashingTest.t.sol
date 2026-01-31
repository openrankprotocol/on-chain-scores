// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {WalletScoreTestBase} from "./WalletScoreTestBase.sol";
import {IWalletScore} from "src/WalletScore/IWalletScore.sol";
import {
    DomainId,
    ScoreSetId,
    RequestId,
    PublisherId,
    BidId,
    BidSelection,
    RequestStatus,
    BidStatus,
    Publisher,
    ScoreRequest,
    Bid,
    Entry
} from "src/WalletScore/Types.sol";

contract SlashingTest is WalletScoreTestBase {
    address internal wallet1 = address(0x1000);

    function setUp() public override {
        super.setUp();
        _setupFullFixture();
    }

    // ============ Bidder Failure Detection ============

    function test_advanceRequest_DetectsExpiredBidder() public {
        RequestId requestId = _createSimpleRequest(1 ether);
        BidId bidId = _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        _assertRequestStatus(requestId, RequestStatus.Assigned);
        _assertBidStatus(bidId, BidStatus.Selected);

        _advancePastBidDeadline(bidId);
        ws.advanceRequest(requestId);

        _assertBidStatus(bidId, BidStatus.Failed);
    }

    function test_advanceRequest_EmitsBidderFailed() public {
        RequestId requestId = _createSimpleRequest(1 ether);
        BidId bidId = _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        _advancePastBidDeadline(bidId);

        vm.expectEmit(true, true, true, false);
        emit IWalletScore.BidderFailed(requestId, bidId, publisher1Id, 0, 0);

        ws.advanceRequest(requestId);
    }

    // ============ Slashing ============

    function test_advanceRequest_SlashesFailedBidderBond() public {
        RequestId requestId = _createSimpleRequest(1 ether);
        BidId bidId = _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        uint256 bondBefore = ws.getPublisherBond(publisher1Id);

        _advancePastBidDeadline(bidId);
        ws.advanceRequest(requestId);

        uint256 bondAfter = ws.getPublisherBond(publisher1Id);
        uint256 slashAmount = 0.5 ether / 2;
        assertEq(bondBefore - bondAfter, slashAmount);
    }

    function test_advanceRequest_SlashCappedAtBondBalance() public {
        vm.prank(publisher1Addr);
        ws.withdrawBond(DEFAULT_BOND - 0.2 ether);

        RequestId requestId = _createSimpleRequest(1 ether);
        BidId bidId = _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        _advancePastBidDeadline(bidId);
        ws.advanceRequest(requestId);

        assertEq(ws.getPublisherBond(publisher1Id), 0);
    }

    // ============ Denylist ============

    function test_advanceRequest_DenylistsFailedBidder() public {
        RequestId requestId = _createSimpleRequest(1 ether);
        BidId bidId = _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        _advancePastBidDeadline(bidId);

        uint256 expectedDenylistEnd = block.timestamp + 1 days;

        ws.advanceRequest(requestId);

        Publisher memory pub = ws.getPublisher(publisher1Id);
        assertGe(pub.denylistUntil, expectedDenylistEnd);
    }

    function test_advanceRequest_EmitsPublisherDenylisted() public {
        RequestId requestId = _createSimpleRequest(1 ether);
        BidId bidId = _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        _advancePastBidDeadline(bidId);

        vm.expectEmit(true, false, false, false);
        emit IWalletScore.PublisherDenylisted(publisher1Id, 0);

        ws.advanceRequest(requestId);
    }

    function test_advanceRequest_DenylistPreventsNewBids() public {
        RequestId request1 = _createSimpleRequest(1 ether);
        BidId bidId = _submitBidAsPublisher1(request1, 0.5 ether, 30 minutes);

        _advancePastQuotingDeadline(request1);
        ws.advanceRequest(request1);

        _advancePastBidDeadline(bidId);
        ws.advanceRequest(request1);

        RequestId request2 = _createSimpleRequest(1 ether);

        Publisher memory pub = ws.getPublisher(publisher1Id);

        vm.prank(publisher1Addr);
        vm.expectRevert(
            abi.encodeWithSelector(IWalletScore.PublisherIsDenylisted.selector, publisher1Id, pub.denylistUntil)
        );
        ws.submitBid(request2, 0.5 ether, 30 minutes);
    }

    // ============ Slash Distribution - No Lost Bidders ============

    function test_advanceRequest_SlashDistribution_NoLostBidders_ToTreasuryAndRequester() public {
        RequestId requestId = _createSimpleRequest(1 ether);
        BidId bidId = _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        uint256 treasuryBefore = ws.getTreasuryBalance();
        uint256 requesterBefore = ws.getWithdrawable(requester1);

        _advancePastBidDeadline(bidId);
        ws.advanceRequest(requestId);

        uint256 slashAmount = 0.5 ether / 2;
        uint256 expectedTreasury = (slashAmount * 40) / 100;
        uint256 expectedRequester = slashAmount - expectedTreasury;

        assertEq(ws.getTreasuryBalance(), treasuryBefore + expectedTreasury);
        assertEq(ws.getWithdrawable(requester1), requesterBefore + expectedRequester + 1 ether);
    }

    function test_advanceRequest_SlashDistribution_EmitsSlashDistributed() public {
        RequestId requestId = _createSimpleRequest(1 ether);
        BidId bidId = _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        _advancePastBidDeadline(bidId);

        vm.expectEmit(true, false, false, false);
        emit IWalletScore.SlashDistributed(requestId, 0, 0, 0);

        ws.advanceRequest(requestId);
    }

    // ============ Slash Distribution - With Next Bidder ============

    function test_advanceRequest_SlashDistribution_NextBidderReceivesShare() public {
        RequestId requestId = _createRequestWithLongerWindow(1 ether);

        BidId bid1 = _submitBidAsPublisher1(requestId, 0.4 ether, 30 minutes);
        _submitBidAsPublisher2(requestId, 0.5 ether, 30 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        uint256 publisher2BondBefore = ws.getPublisherBond(publisher2Id);

        _advancePastBidDeadline(bid1);
        ws.advanceRequest(requestId);

        uint256 slashAmount = 0.4 ether / 2;
        uint256 expectedToNext = (slashAmount * 60) / 100;

        assertGe(ws.getPublisherBond(publisher2Id), publisher2BondBefore + expectedToNext - 1);
    }

    function test_advanceRequest_SelectsNextBidderAfterSlash() public {
        RequestId requestId = _createRequestWithLongerWindow(1 ether);

        BidId bid1 = _submitBidAsPublisher1(requestId, 0.4 ether, 30 minutes);
        BidId bid2 = _submitBidAsPublisher2(requestId, 0.5 ether, 30 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        _assertBidStatus(bid1, BidStatus.Selected);

        _advancePastBidDeadline(bid1);
        ws.advanceRequest(requestId);

        _assertBidStatus(bid1, BidStatus.Failed);
        _assertBidStatus(bid2, BidStatus.Selected);
        _assertRequestStatus(requestId, RequestStatus.Assigned);
    }

    // ============ Lost Bidder Compensation ============

    /// @notice Test exact slash distribution with one lost bidder
    /// Scenario: Publisher1 (10 min) selected, Publisher2 (24 min) becomes lost,
    /// Publisher3 (15 min) becomes next bidder
    /// Distribution: 20% treasury, 50% to lost bidder (Publisher2), 30% to next (Publisher3)
    function test_lostBidder_SingleLostBidder_ExactDistribution() public {
        // Create request with tight window: quoting +60min, fulfillment +90min
        // After quoting (at ~60min), only 30 min left until deadline
        RequestId requestId = _createRequestForLostBidderTest(1 ether);

        // Publisher1: cheapest, 10 min duration (will be selected)
        BidId bid1 = _submitBidAsPublisher1(requestId, 0.3 ether, 10 minutes);
        // Publisher2: 24 min promise (valid at selection: 60+24=84 < 90, lost at 70: 70+24=94 >= 90)
        _submitBidAsPublisher2(requestId, 0.4 ether, 24 minutes);
        // Publisher3: 15 min promise (valid at selection and after: 70+15=85 < 90)
        _submitBidAsPublisher3(requestId, 0.5 ether, 15 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        // Record state before slash
        uint256 pub2BondBefore = ws.getPublisherBond(publisher2Id);
        uint256 pub3BondBefore = ws.getPublisherBond(publisher3Id);
        uint256 treasuryBefore = ws.getTreasuryBalance();

        // Publisher1 fails after their promised duration
        // At this point Publisher2 can no longer fulfill (24 min > remaining ~20 min)
        // Publisher3 still can (15 min < remaining ~20 min)
        _advancePastBidDeadline(bid1);
        ws.advanceRequest(requestId);

        // Slash = 0.3 ether / 2 = 0.15 ether
        uint256 slashAmount = 0.15 ether;
        uint256 expectedTreasury = (slashAmount * 20) / 100; // 0.03 ether
        uint256 expectedLostBidders = (slashAmount * 50) / 100; // 0.075 ether
        uint256 expectedNext = slashAmount - expectedTreasury - expectedLostBidders; // 0.045 ether

        // Verify treasury received 20%
        assertEq(ws.getTreasuryBalance(), treasuryBefore + expectedTreasury, "Treasury should receive 20% of slash");

        // Verify Publisher2 (lost bidder) received 50%
        assertEq(
            ws.getPublisherBond(publisher2Id),
            pub2BondBefore + expectedLostBidders,
            "Lost bidder should receive 50% of slash"
        );

        // Verify Publisher3 (next bidder) received 30%
        assertEq(
            ws.getPublisherBond(publisher3Id), pub3BondBefore + expectedNext, "Next bidder should receive 30% of slash"
        );
    }

    /// @notice Test proportional distribution among multiple lost bidders
    /// Distribution to lost bidders is proportional to their quoted prices
    function test_lostBidder_MultipleLostBidders_ProportionalDistribution() public {
        // Tight window: quoting +60min, fulfillment +90min
        RequestId requestId = _createRequestForLostBidderTest(1 ether);

        // Publisher1: 5 min promise (will be selected)
        BidId bid1 = _submitBidAsPublisher1(requestId, 0.2 ether, 5 minutes);
        // Publisher2: 28 min promise, quoted 0.3 ether (valid at 60: 88<90, lost at 65: 93>=90)
        _submitBidAsPublisher2(requestId, 0.3 ether, 28 minutes);
        // Publisher3: 26 min promise, quoted 0.6 ether (valid at 60: 86<90, lost at 65: 91>=90)
        _submitBidAsPublisher3(requestId, 0.6 ether, 26 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        uint256 pub2BondBefore = ws.getPublisherBond(publisher2Id);
        uint256 pub3BondBefore = ws.getPublisherBond(publisher3Id);

        // Publisher1 fails after their promised duration, both Publisher2 and Publisher3 become lost
        // (no next bidder available)
        _advancePastBidDeadline(bid1);
        ws.advanceRequest(requestId);

        // Slash = 0.2 ether / 2 = 0.1 ether
        uint256 slashAmount = 0.1 ether;
        uint256 toLostBidders = (slashAmount * 50) / 100; // 0.05 ether

        // Proportional distribution based on quoted prices:
        // Publisher2 quoted 0.3, Publisher3 quoted 0.6, total = 0.9 ether
        // Publisher2 share: 0.05 * (0.3 / 0.9) = 0.05 * 1/3 ≈ 0.0166 ether
        // Publisher3 share: 0.05 * (0.6 / 0.9) = 0.05 * 2/3 ≈ 0.0333 ether
        uint256 totalQuoted = 0.9 ether;
        uint256 pub2ExpectedShare = (toLostBidders * 0.3 ether) / totalQuoted;
        uint256 pub3ExpectedShare = toLostBidders - pub2ExpectedShare; // remainder to avoid rounding

        uint256 pub2BondAfter = ws.getPublisherBond(publisher2Id);
        uint256 pub3BondAfter = ws.getPublisherBond(publisher3Id);

        // Check proportional distribution (allowing 1 wei tolerance for rounding)
        assertApproxEqAbs(
            pub2BondAfter - pub2BondBefore, pub2ExpectedShare, 1, "Publisher2 should receive proportional share"
        );
        assertApproxEqAbs(
            pub3BondAfter - pub3BondBefore,
            pub3ExpectedShare,
            1,
            "Publisher3 should receive proportional share (remainder)"
        );

        // Verify total distributed equals 50% of slash
        uint256 totalDistributed = (pub2BondAfter - pub2BondBefore) + (pub3BondAfter - pub3BondBefore);
        assertEq(totalDistributed, toLostBidders, "Total to lost bidders should be 50% of slash");
    }

    /// @notice End-to-end: Lost bidder gets compensation, next bidder fulfills
    function test_lostBidder_CompensationThenFulfillment() public {
        // Tight window: quoting +60min, fulfillment +90min
        RequestId requestId = _createRequestForLostBidderTest(1 ether);

        // Publisher1: 10 min (selected, will fail)
        BidId bid1 = _submitBidAsPublisher1(requestId, 0.3 ether, 10 minutes);
        // Publisher2: 24 min (will become lost: 70+24=94 >= 90)
        _submitBidAsPublisher2(requestId, 0.4 ether, 24 minutes);
        // Publisher3: 15 min (will become next: 70+15=85 < 90)
        _submitBidAsPublisher3(requestId, 0.5 ether, 15 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        uint256 pub2BondBefore = ws.getPublisherBond(publisher2Id);
        uint256 pub3BondBefore = ws.getPublisherBond(publisher3Id);
        uint256 pub3WithdrawableBefore = ws.getWithdrawable(publisher3Addr);

        // Publisher1 fails after their promised duration, Publisher2 becomes lost, Publisher3 becomes next
        _advancePastBidDeadline(bid1);
        ws.advanceRequest(requestId);

        // Verify Publisher2 got lost bidder compensation (50%)
        uint256 slashAmount = 0.15 ether;
        uint256 expectedLostCompensation = (slashAmount * 50) / 100;
        assertEq(
            ws.getPublisherBond(publisher2Id),
            pub2BondBefore + expectedLostCompensation,
            "Lost bidder (Publisher2) should receive 50% compensation"
        );

        // Verify Publisher3 got next bidder bonus (30%)
        uint256 expectedNextBonus = slashAmount - (slashAmount * 20) / 100 - expectedLostCompensation;
        assertEq(
            ws.getPublisherBond(publisher3Id),
            pub3BondBefore + expectedNextBonus,
            "Next bidder (Publisher3) should receive 30% bonus to bond"
        );

        // Publisher3 fulfills
        _fulfillAsPublisher3(requestId);

        // Publisher3 should receive their quoted fee
        assertEq(
            ws.getWithdrawable(publisher3Addr),
            pub3WithdrawableBefore + 0.5 ether,
            "Publisher3 should receive quoted fee after fulfillment"
        );

        _assertRequestStatus(requestId, RequestStatus.Fulfilled);
    }

    /// @notice Verify configurable slash distribution parameters work correctly
    function test_lostBidder_ConfigurableDistributionParams() public {
        // Change distribution to: 10% treasury, 70% lost bidders, 20% next
        vm.prank(admin);
        ws.setSlashDistributionParams(40, 10, 70); // (noLost treasury, withLost treasury, lostBidders)

        // Tight window for lost bidder scenario
        RequestId requestId = _createRequestForLostBidderTest(1 ether);

        // Publisher1: 10 min (selected)
        BidId bid1 = _submitBidAsPublisher1(requestId, 0.4 ether, 10 minutes);
        // Publisher2: 24 min (will become lost)
        _submitBidAsPublisher2(requestId, 0.5 ether, 24 minutes);
        // Publisher3: 15 min (will become next)
        _submitBidAsPublisher3(requestId, 0.6 ether, 15 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        uint256 pub2BondBefore = ws.getPublisherBond(publisher2Id);
        uint256 pub3BondBefore = ws.getPublisherBond(publisher3Id);
        uint256 treasuryBefore = ws.getTreasuryBalance();

        // Publisher1 fails after their promised duration
        _advancePastBidDeadline(bid1);
        ws.advanceRequest(requestId);

        // Slash = 0.4 / 2 = 0.2 ether
        uint256 slashAmount = 0.2 ether;
        uint256 expectedTreasury = (slashAmount * 10) / 100; // 10% = 0.02 ether
        uint256 expectedLost = (slashAmount * 70) / 100; // 70% = 0.14 ether
        uint256 expectedNext = slashAmount - expectedTreasury - expectedLost; // 20% = 0.04 ether

        assertEq(ws.getTreasuryBalance(), treasuryBefore + expectedTreasury, "Custom treasury %");
        assertEq(ws.getPublisherBond(publisher2Id), pub2BondBefore + expectedLost, "Custom lost bidder %");
        assertEq(ws.getPublisherBond(publisher3Id), pub3BondBefore + expectedNext, "Custom next bidder %");
    }

    // ============ Multiple Failures ============

    function test_advanceRequest_MultipleFailuresSlashMultipleTimes() public {
        RequestId requestId = _createRequestWithLongerWindow(1 ether);

        BidId bid1 = _submitBidAsPublisher1(requestId, 0.3 ether, 15 minutes);
        BidId bid2 = _submitBidAsPublisher2(requestId, 0.4 ether, 15 minutes);
        BidId bid3 = _submitBidAsPublisher3(requestId, 0.5 ether, 15 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        uint256 bond1Before = ws.getPublisherBond(publisher1Id);
        _advancePastBidDeadline(bid1);
        ws.advanceRequest(requestId);
        assertLt(ws.getPublisherBond(publisher1Id), bond1Before);
        _assertBidStatus(bid2, BidStatus.Selected);

        uint256 bond2Before = ws.getPublisherBond(publisher2Id);
        _advancePastBidDeadline(bid2);
        ws.advanceRequest(requestId);
        assertLt(ws.getPublisherBond(publisher2Id), bond2Before);
        _assertBidStatus(bid3, BidStatus.Selected);

        uint256 bond3Before = ws.getPublisherBond(publisher3Id);
        _advancePastBidDeadline(bid3);
        ws.advanceRequest(requestId);
        assertLt(ws.getPublisherBond(publisher3Id), bond3Before);

        _assertRequestStatus(requestId, RequestStatus.Failed);
    }

    function test_advanceRequest_AllBiddersFailRefundsRequester() public {
        RequestId requestId = _createSimpleRequest(1 ether);
        BidId bidId = _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        _advancePastBidDeadline(bidId);
        ws.advanceRequest(requestId);

        _assertRequestStatus(requestId, RequestStatus.Failed);
        assertGe(ws.getWithdrawable(requester1), 1 ether);
    }

    // ============ Treasury Withdrawal ============

    function test_withdrawTreasury_Success() public {
        RequestId requestId = _createSimpleRequest(1 ether);
        BidId bidId = _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        _advancePastBidDeadline(bidId);
        ws.advanceRequest(requestId);

        uint256 treasuryBalance = ws.getTreasuryBalance();
        assertTrue(treasuryBalance > 0);

        uint256 adminBalanceBefore = admin.balance;

        vm.prank(admin);
        ws.withdrawTreasury(admin, treasuryBalance);

        assertEq(admin.balance, adminBalanceBefore + treasuryBalance);
        assertEq(ws.getTreasuryBalance(), 0);
    }

    function test_withdrawTreasury_RevertWhenNotAdmin() public {
        vm.prank(nobody);
        vm.expectRevert();
        ws.withdrawTreasury(nobody, 1 ether);
    }

    function test_withdrawTreasury_RevertWhenInsufficientBalance() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.InsufficientTreasuryBalance.selector, 1 ether, 0));
        ws.withdrawTreasury(admin, 1 ether);
    }

    // ============ Recovery Scenarios (End-to-End) ============

    /// @notice First bidder fails, second bidder fulfills and earns fee + slash spillover
    function test_recovery_FirstFailsSecondFulfills() public {
        // Create request with enough time for multiple bidders
        RequestId requestId = _createRequestWithLongerWindow(1 ether);

        // Publisher1 bids cheaper (will be selected first), Publisher2 bids higher
        BidId bid1 = _submitBidAsPublisher1(requestId, 0.4 ether, 30 minutes);
        BidId bid2 = _submitBidAsPublisher2(requestId, 0.5 ether, 30 minutes);

        // Advance past quoting, select cheapest bidder (Publisher1)
        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        _assertBidStatus(bid1, BidStatus.Selected);
        _assertBidStatus(bid2, BidStatus.Pending);

        // Record Publisher2's state before slash
        uint256 pub2BondBefore = ws.getPublisherBond(publisher2Id);
        uint256 pub2WithdrawableBefore = ws.getWithdrawable(publisher2Addr);

        // Publisher1 fails to deliver
        _advancePastBidDeadline(bid1);
        ws.advanceRequest(requestId);

        // Publisher1 slashed, Publisher2 selected as next bidder
        _assertBidStatus(bid1, BidStatus.Failed);
        _assertBidStatus(bid2, BidStatus.Selected);

        // Publisher2 received slash spillover: 60% of (0.4 ether / 2) = 0.12 ether
        assertEq(
            ws.getPublisherBond(publisher2Id), pub2BondBefore + 0.12 ether, "Publisher2 should receive slash spillover"
        );

        // Publisher2 creates score set and fulfills
        _fulfillAsPublisher2(requestId);

        // Verify final state
        _assertRequestStatus(requestId, RequestStatus.Fulfilled);
        _assertBidStatus(bid2, BidStatus.Won);

        // Publisher2 should have: original bond + slash spillover (bond), + bid price (withdrawable)
        assertEq(
            ws.getWithdrawable(publisher2Addr),
            pub2WithdrawableBefore + 0.5 ether,
            "Publisher2 should receive their quoted fee"
        );
    }

    /// @notice First and second bidders fail, third bidder fulfills and earns fee + slash spillovers
    function test_recovery_FirstAndSecondFailThirdFulfills() public {
        // Create request with wide window to accommodate 3 bidders failing sequentially
        RequestId requestId = _createRequestWithWideWindow(1 ether);

        // Three bidders with increasing prices
        BidId bid1 = _submitBidAsPublisher1(requestId, 0.3 ether, 30 minutes);
        BidId bid2 = _submitBidAsPublisher2(requestId, 0.4 ether, 30 minutes);
        BidId bid3 = _submitBidAsPublisher3(requestId, 0.5 ether, 30 minutes);

        // Advance past quoting, Publisher1 selected
        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);
        _assertBidStatus(bid1, BidStatus.Selected);

        uint256 pub2BondBefore = ws.getPublisherBond(publisher2Id);

        // Publisher1 fails → Publisher2 selected, receives 60% of slash1
        _advancePastBidDeadline(bid1);
        ws.advanceRequest(requestId);

        _assertBidStatus(bid1, BidStatus.Failed);
        _assertBidStatus(bid2, BidStatus.Selected);

        // Publisher2 received 60% of slash1: 60% of (0.3 ether / 2) = 0.09 ether
        assertEq(
            ws.getPublisherBond(publisher2Id), pub2BondBefore + 0.09 ether, "Publisher2 should receive slash1 spillover"
        );

        // Record Publisher3's state before second slash
        uint256 pub3BondBefore = ws.getPublisherBond(publisher3Id);
        uint256 pub3WithdrawableBefore = ws.getWithdrawable(publisher3Addr);

        // Publisher2 also fails → Publisher3 selected, receives 60% of slash2
        _advancePastBidDeadline(bid2);
        ws.advanceRequest(requestId);

        _assertBidStatus(bid2, BidStatus.Failed);
        _assertBidStatus(bid3, BidStatus.Selected);

        // Publisher3 received 60% of slash2: 60% of (0.4 ether / 2) = 0.12 ether
        assertEq(
            ws.getPublisherBond(publisher3Id), pub3BondBefore + 0.12 ether, "Publisher3 should receive slash2 spillover"
        );

        // Publisher3 creates score set and fulfills
        _fulfillAsPublisher3(requestId);

        // Verify final state
        _assertRequestStatus(requestId, RequestStatus.Fulfilled);
        _assertBidStatus(bid3, BidStatus.Won);

        // Publisher3 should receive their quoted fee
        assertEq(
            ws.getWithdrawable(publisher3Addr),
            pub3WithdrawableBefore + 0.5 ether,
            "Publisher3 should receive their quoted fee"
        );

        // Verify requester got refund of excess budget
        // Budget was 1 ether, Publisher3 charged 0.5 ether → 0.5 ether refund
        assertGe(ws.getWithdrawable(requester1), 0.5 ether, "Requester should receive at least the excess budget");
    }

    function _fulfillAsPublisher2(RequestId requestId) internal {
        Entry[] memory entries = _buildSampleEntries(1);
        entries[0].wallet = wallet1;
        ScoreSetId scoreSetId =
            _createAndPublishScoreSetWithEntries(publisher2Addr, domainAvici, block.timestamp, entries);
        vm.prank(publisher2Addr);
        ws.fulfillRequest(requestId, scoreSetId);
    }

    function _fulfillAsPublisher3(RequestId requestId) internal {
        Entry[] memory entries = _buildSampleEntries(1);
        entries[0].wallet = wallet1;
        ScoreSetId scoreSetId =
            _createAndPublishScoreSetWithEntries(publisher3Addr, domainAvici, block.timestamp, entries);
        vm.prank(publisher3Addr);
        ws.fulfillRequest(requestId, scoreSetId);
    }

    // ============ Helpers ============

    function _createRequestWithLongerWindow(uint256 budget) internal returns (RequestId) {
        address[] memory wallets = _singleWalletArray(wallet1);

        vm.prank(requester1);
        return ws.createRequest{value: budget}(
            domainAvici,
            wallets,
            0,
            0,
            block.timestamp - 1 days,
            block.timestamp + 1 days,
            block.timestamp + 1 hours,
            block.timestamp + 3 hours,
            BidSelection.Cheapest
        );
    }

    function _createRequestWithMediumWindow(uint256 budget) internal returns (RequestId) {
        address[] memory wallets = _singleWalletArray(wallet1);

        vm.prank(requester1);
        return ws.createRequest{value: budget}(
            domainAvici,
            wallets,
            0,
            0,
            block.timestamp - 1 days,
            block.timestamp + 1 days,
            block.timestamp + 1 hours,
            block.timestamp + 100 minutes,
            BidSelection.Cheapest
        );
    }

    function _createRequestWithWideWindow(uint256 budget) internal returns (RequestId) {
        address[] memory wallets = _singleWalletArray(wallet1);

        vm.prank(requester1);
        return ws.createRequest{value: budget}(
            domainAvici,
            wallets,
            0,
            0,
            block.timestamp - 1 days,
            block.timestamp + 1 days,
            block.timestamp + 1 hours,
            block.timestamp + 4 hours,
            BidSelection.Cheapest
        );
    }

    /// @notice Creates a request with a tight window designed for lost bidder testing
    /// Quoting: +60min, Fulfillment: +90min (only 30min after quoting)
    function _createRequestForLostBidderTest(uint256 budget) internal returns (RequestId) {
        address[] memory wallets = _singleWalletArray(wallet1);

        vm.prank(requester1);
        return ws.createRequest{value: budget}(
            domainAvici,
            wallets,
            0,
            0,
            block.timestamp - 1 days,
            block.timestamp + 1 days,
            block.timestamp + 60 minutes,
            block.timestamp + 90 minutes,
            BidSelection.Cheapest
        );
    }
}

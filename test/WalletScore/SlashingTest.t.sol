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

    // ============ Lost Bidders ============

    function test_advanceRequest_SlashDistribution_WithLostBidders() public {
        RequestId requestId = _createRequestWithWideWindow(1 ether);

        _submitBidAsPublisher1(requestId, 0.3 ether, 20 minutes);
        _submitBidAsPublisher2(requestId, 0.4 ether, 50 minutes);
        _submitBidAsPublisher3(requestId, 0.5 ether, 70 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        uint256 pub2BondBefore = ws.getPublisherBond(publisher2Id);
        uint256 pub3BondBefore = ws.getPublisherBond(publisher3Id);
        uint256 treasuryBefore = ws.getTreasuryBalance();

        skip(45 minutes);
        ws.advanceRequest(requestId);

        uint256 slashAmount = 0.3 ether / 2;
        uint256 toTreasury = (slashAmount * 20) / 100;

        assertGe(ws.getTreasuryBalance(), treasuryBefore + toTreasury - 1);

        uint256 pub2BondAfter = ws.getPublisherBond(publisher2Id);
        uint256 pub3BondAfter = ws.getPublisherBond(publisher3Id);
        assertTrue(pub2BondAfter > pub2BondBefore || pub3BondAfter > pub3BondBefore);
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

    // ============ Helpers ============

    function _createRequestWithLongerWindow(uint256 budget) internal returns (RequestId) {
        address[] memory wallets = _singleWalletArray(wallet1);

        vm.prank(requester1);
        return ws.createRequest{value: budget}(
            domainAvici,
            wallets,
            0, 0,
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
            0, 0,
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
            0, 0,
            block.timestamp - 1 days,
            block.timestamp + 1 days,
            block.timestamp + 1 hours,
            block.timestamp + 4 hours,
            BidSelection.Cheapest
        );
    }
}

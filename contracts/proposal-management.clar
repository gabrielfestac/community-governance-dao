;; Proposal Management Contract
;; Handles proposal creation, voting, execution, and lifecycle management
;; Supports multiple proposal types with comprehensive governance workflows

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u4001))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u4002))
(define-constant ERR-INVALID-PROPOSAL-TYPE (err u4003))
(define-constant ERR-PROPOSAL-EXPIRED (err u4004))
(define-constant ERR-PROPOSAL-NOT-ACTIVE (err u4005))
(define-constant ERR-ALREADY-VOTED (err u4006))
(define-constant ERR-VOTING-PERIOD-ENDED (err u4007))
(define-constant ERR-INSUFFICIENT-VOTING-POWER (err u4008))
(define-constant ERR-QUORUM-NOT-MET (err u4009))
(define-constant ERR-PROPOSAL-FAILED (err u4010))
(define-constant ERR-EXECUTION-FAILED (err u4011))
(define-constant ERR-PROPOSAL-ALREADY-EXECUTED (err u4012))
(define-constant ERR-EXECUTION-DELAY-NOT-MET (err u4013))
(define-constant ERR-INVALID-VOTE_TYPE (err u4014))
(define-constant ERR-PROPOSAL-CANCELLED (err u4015))
(define-constant ERR-CANNOT-CANCEL (err u4016))
(define-constant ERR-INVALID-THRESHOLD (err u4017))
(define-constant ERR-DUPLICATE-PROPOSAL (err u4018))
(define-constant ERR-EMERGENCY_PROPOSAL_ONLY (err u4019))

;; Proposal Types
(define-constant PROPOSAL-TYPE-TREASURY "treasury")
(define-constant PROPOSAL-TYPE-PARAMETER "parameter")
(define-constant PROPOSAL-TYPE-MEMBERSHIP "membership")
(define-constant PROPOSAL-TYPE-UPGRADE "upgrade")
(define-constant PROPOSAL-TYPE-EMERGENCY "emergency")
(define-constant PROPOSAL-TYPE-GENERAL "general")

;; Proposal Status
(define-constant PROPOSAL-STATUS-DRAFT "draft")
(define-constant PROPOSAL-STATUS-ACTIVE "active")
(define-constant PROPOSAL-STATUS-PASSED "passed")
(define-constant PROPOSAL-STATUS-FAILED "failed")
(define-constant PROPOSAL-STATUS-EXECUTED "executed")
(define-constant PROPOSAL-STATUS-CANCELLED "cancelled")
(define-constant PROPOSAL-STATUS-EXPIRED "expired")

;; Vote Types
(define-constant VOTE-FOR "for")
(define-constant VOTE-AGAINST "against")
(define-constant VOTE-ABSTAIN "abstain")

;; Default Parameters
(define-constant DEFAULT-VOTING-PERIOD u1440) ;; ~1 week
(define-constant DEFAULT-EXECUTION-DELAY u720) ;; ~3.5 days
(define-constant DEFAULT-QUORUM-THRESHOLD u20) ;; 20%
(define-constant DEFAULT-PASSING-THRESHOLD u50) ;; 50%

;; Data Variables
(define-data-var next-proposal-id uint u1)
(define-data-var total-proposals uint u0)
(define-data-var active-proposals uint u0)
(define-data-var proposals-executed uint u0)
(define-data-var emergency-proposals-count uint u0)

;; Governance contract reference (would be set during deployment)
(define-data-var governance-contract principal tx-sender)

;; Data Maps

;; Main Proposals Registry
(define-map proposals
  { proposal-id: uint }
  {
    proposer: principal,
    proposal-type: (string-ascii 20),
    title: (string-ascii 200),
    description: (string-ascii 1000),
    metadata-uri: (optional (string-ascii 200)),
    target-contract: (optional principal),
    function-call: (optional (string-ascii 100)),
    parameters: (optional (string-ascii 500)),
    status: (string-ascii 20),
    created-at: uint,
    voting-starts-at: uint,
    voting-ends-at: uint,
    execution-delay: uint,
    quorum-threshold: uint,
    passing-threshold: uint,
    emergency: bool
  }
)

;; Proposal Votes
(define-map proposal-votes
  { proposal-id: uint, voter: principal }
  {
    vote-type: (string-ascii 10),
    voting-power: uint,
    vote-timestamp: uint,
    reason: (optional (string-ascii 500))
  }
)

;; Proposal Vote Tallies
(define-map proposal-tallies
  { proposal-id: uint }
  {
    votes-for: uint,
    votes-against: uint,
    votes-abstain: uint,
    total-votes: uint,
    unique-voters: uint,
    voting-power-for: uint,
    voting-power-against: uint,
    voting-power-abstain: uint,
    total-voting-power: uint
  }
)

;; Treasury Proposals (specific details)
(define-map treasury-proposals
  { proposal-id: uint }
  {
    recipient: principal,
    amount: uint,
    purpose: (string-ascii 200),
    payment-schedule: (optional (string-ascii 100)),
    milestones: (optional (string-ascii 500))
  }
)

;; Parameter Proposals (specific details)
(define-map parameter-proposals
  { proposal-id: uint }
  {
    parameter-name: (string-ascii 50),
    current-value: uint,
    proposed-value: uint,
    rationale: (string-ascii 500)
  }
)

;; Membership Proposals (specific details)
(define-map membership-proposals
  { proposal-id: uint }
  {
    target-member: principal,
    action: (string-ascii 20), ;; "add", "remove", "suspend", "restore"
    new-stake-requirement: (optional uint),
    reason: (string-ascii 300)
  }
)

;; Upgrade Proposals (specific details)
(define-map upgrade-proposals
  { proposal-id: uint }
  {
    contract-to-upgrade: principal,
    new-contract-source: (string-ascii 500),
    migration-plan: (string-ascii 500),
    testing-period: uint,
    rollback-plan: (string-ascii 300)
  }
)

;; Proposal Execution Log
(define-map proposal-executions
  { proposal-id: uint }
  {
    executed-by: principal,
    execution-timestamp: uint,
    execution-result: bool,
    gas-used: uint,
    execution-notes: (optional (string-ascii 300))
  }
)

;; Proposal Comments/Discussion
(define-map proposal-comments
  { proposal-id: uint, comment-id: uint }
  {
    commenter: principal,
    comment: (string-ascii 500),
    timestamp: uint,
    reply-to: (optional uint)
  }
)

;; Proposal Amendments
(define-map proposal-amendments
  { proposal-id: uint, amendment-id: uint }
  {
    proposer: principal,
    amendment-description: (string-ascii 500),
    amendment-data: (string-ascii 1000),
    proposed-at: uint,
    status: (string-ascii 20),
    votes-for: uint,
    votes-against: uint
  }
)

;; Private Functions

(define-private (is-contract-owner (caller principal))
  (is-eq caller CONTRACT-OWNER)
)

(define-private (is-proposal-active (proposal-id uint))
  (match (map-get? proposals {proposal-id: proposal-id})
    proposal-data
    (and
      (is-eq (get status proposal-data) PROPOSAL-STATUS-ACTIVE)
      (>= stacks-block-height (get voting-starts-at proposal-data))
      (< stacks-block-height (get voting-ends-at proposal-data))
    )
    false
  )
)

(define-private (can-vote (voter principal) (proposal-id uint))
  (and
    ;; Check if voting period is active
    (is-proposal-active proposal-id)
    ;; Check if user hasn't voted yet
    (is-none (map-get? proposal-votes {proposal-id: proposal-id, voter: voter}))
    ;; Check if user is active member (would call governance contract)
    true ;; Placeholder - would integrate with governance contract
  )
)

(define-private (get-voter-power (voter principal))
  ;; This would call the governance contract to get actual voting power
  ;; For now, returning a placeholder
  u100
)

(define-private (calculate-vote-outcome (proposal-id uint))
  (match (map-get? proposal-tallies {proposal-id: proposal-id})
    tally
    (let ((total-power (get total-voting-power tally))
          (quorum-met (>= total-power (/ (* (get quorum-threshold (unwrap-panic (map-get? proposals {proposal-id: proposal-id}))) total-power) u100)))
          (votes-for (get voting-power-for tally))
          (votes-against (get voting-power-against tally))
          (passing-threshold (get passing-threshold (unwrap-panic (map-get? proposals {proposal-id: proposal-id})))))
      (if quorum-met
        (>= (* votes-for u100) (* (+ votes-for votes-against) passing-threshold))
        false
      )
    )
    false
  )
)

(define-private (update-proposal-tally (proposal-id uint) (vote-type (string-ascii 10)) (voting-power uint))
  (let ((current-tally (default-to 
                        {votes-for: u0, votes-against: u0, votes-abstain: u0, total-votes: u0,
                         unique-voters: u0, voting-power-for: u0, voting-power-against: u0,
                         voting-power-abstain: u0, total-voting-power: u0}
                        (map-get? proposal-tallies {proposal-id: proposal-id}))))
    (map-set proposal-tallies
      {proposal-id: proposal-id}
      (if (is-eq vote-type VOTE-FOR)
        (merge current-tally {
          votes-for: (+ (get votes-for current-tally) u1),
          voting-power-for: (+ (get voting-power-for current-tally) voting-power),
          total-votes: (+ (get total-votes current-tally) u1),
          unique-voters: (+ (get unique-voters current-tally) u1),
          total-voting-power: (+ (get total-voting-power current-tally) voting-power)
        })
        (if (is-eq vote-type VOTE-AGAINST)
          (merge current-tally {
            votes-against: (+ (get votes-against current-tally) u1),
            voting-power-against: (+ (get voting-power-against current-tally) voting-power),
            total-votes: (+ (get total-votes current-tally) u1),
            unique-voters: (+ (get unique-voters current-tally) u1),
            total-voting-power: (+ (get total-voting-power current-tally) voting-power)
          })
          (merge current-tally {
            votes-abstain: (+ (get votes-abstain current-tally) u1),
            voting-power-abstain: (+ (get voting-power-abstain current-tally) voting-power),
            total-votes: (+ (get total-votes current-tally) u1),
            unique-voters: (+ (get unique-voters current-tally) u1),
            total-voting-power: (+ (get total-voting-power current-tally) voting-power)
          })
        )
      )
    )
  )
)

;; Public Functions

;; Proposal Creation

(define-public (create-proposal
  (proposal-type (string-ascii 20))
  (title (string-ascii 200))
  (description (string-ascii 1000))
  (metadata-uri (optional (string-ascii 200)))
  (voting-period (optional uint))
  (execution-delay (optional uint))
  (emergency bool)
)
  (let ((proposal-id (var-get next-proposal-id))
        (voting-starts (+ stacks-block-height u1))
        (voting-duration (default-to DEFAULT-VOTING-PERIOD voting-period))
        (exec-delay (default-to DEFAULT-EXECUTION-DELAY execution-delay)))
    (if (and
          ;; Check if proposer has sufficient voting power
          (>= (get-voter-power tx-sender) u10) ;; Minimum threshold
          ;; Validate proposal type
          (or (is-eq proposal-type PROPOSAL-TYPE-TREASURY)
              (is-eq proposal-type PROPOSAL-TYPE-PARAMETER)
              (is-eq proposal-type PROPOSAL-TYPE-MEMBERSHIP)
              (is-eq proposal-type PROPOSAL-TYPE-UPGRADE)
              (is-eq proposal-type PROPOSAL-TYPE-EMERGENCY)
              (is-eq proposal-type PROPOSAL-TYPE-GENERAL))
        )
      (begin
        (map-set proposals
          {proposal-id: proposal-id}
          {
            proposer: tx-sender,
            proposal-type: proposal-type,
            title: title,
            description: description,
            metadata-uri: metadata-uri,
            target-contract: none,
            function-call: none,
            parameters: none,
            status: PROPOSAL-STATUS-ACTIVE,
            created-at: stacks-block-height,
            voting-starts-at: voting-starts,
            voting-ends-at: (+ voting-starts voting-duration),
            execution-delay: exec-delay,
            quorum-threshold: DEFAULT-QUORUM-THRESHOLD,
            passing-threshold: DEFAULT-PASSING-THRESHOLD,
            emergency: emergency
          }
        )
        (var-set next-proposal-id (+ proposal-id u1))
        (var-set total-proposals (+ (var-get total-proposals) u1))
        (var-set active-proposals (+ (var-get active-proposals) u1))
        (if emergency
          (var-set emergency-proposals-count (+ (var-get emergency-proposals-count) u1))
          true
        )
        (ok proposal-id)
      )
      (err ERR-NOT-AUTHORIZED)
    )
  )
)

(define-public (create-treasury-proposal
  (title (string-ascii 200))
  (description (string-ascii 1000))
  (recipient principal)
  (amount uint)
  (purpose (string-ascii 200))
)
  (let ((proposal-result (try! (create-proposal PROPOSAL-TYPE-TREASURY title description none none none false))))
    (map-set treasury-proposals
      {proposal-id: proposal-result}
      {
        recipient: recipient,
        amount: amount,
        purpose: purpose,
        payment-schedule: none,
        milestones: none
      }
    )
    (ok proposal-result)
  )
)

(define-public (create-parameter-proposal
  (title (string-ascii 200))
  (description (string-ascii 1000))
  (parameter-name (string-ascii 50))
  (proposed-value uint)
  (rationale (string-ascii 500))
)
  (let ((proposal-result (try! (create-proposal PROPOSAL-TYPE-PARAMETER title description none none none false))))
    (map-set parameter-proposals
      {proposal-id: proposal-result}
      {
        parameter-name: parameter-name,
        current-value: u0, ;; Would be retrieved from governance contract
        proposed-value: proposed-value,
        rationale: rationale
      }
    )
    (ok proposal-result)
  )
)

;; Voting Functions

(define-public (vote (proposal-id uint) (vote-type (string-ascii 10)) (reason (optional (string-ascii 500))))
  (let ((voting-power (get-voter-power tx-sender)))
    (if (and
          (can-vote tx-sender proposal-id)
          (or (is-eq vote-type VOTE-FOR) (is-eq vote-type VOTE-AGAINST) (is-eq vote-type VOTE-ABSTAIN))
          (> voting-power u0)
        )
      (begin
        ;; Record the vote
        (map-set proposal-votes
          {proposal-id: proposal-id, voter: tx-sender}
          {
            vote-type: vote-type,
            voting-power: voting-power,
            vote-timestamp: stacks-block-height,
            reason: reason
          }
        )
        ;; Update vote tallies
        (update-proposal-tally proposal-id vote-type voting-power)
        (ok true)
      )
      (err ERR-ALREADY-VOTED)
    )
  )
)

(define-public (finalize-proposal (proposal-id uint))
  (let ((proposal-data (unwrap! (map-get? proposals {proposal-id: proposal-id}) (err ERR-PROPOSAL-NOT-FOUND))))
    (if (and
          (is-eq (get status proposal-data) PROPOSAL-STATUS-ACTIVE)
          (>= stacks-block-height (get voting-ends-at proposal-data))
        )
      (let ((outcome (calculate-vote-outcome proposal-id))
            (new-status (if outcome PROPOSAL-STATUS-PASSED PROPOSAL-STATUS-FAILED)))
        (map-set proposals
          {proposal-id: proposal-id}
          (merge proposal-data {
            status: new-status
          })
        )
        (var-set active-proposals (- (var-get active-proposals) u1))
        (ok outcome)
      )
      (err ERR-PROPOSAL-NOT-ACTIVE)
    )
  )
)

;; Proposal Execution

(define-public (execute-proposal (proposal-id uint))
  (let ((proposal-data (unwrap! (map-get? proposals {proposal-id: proposal-id}) (err ERR-PROPOSAL-NOT-FOUND))))
    (if (and
          (is-eq (get status proposal-data) PROPOSAL-STATUS-PASSED)
          (>= stacks-block-height (+ (get voting-ends-at proposal-data) (get execution-delay proposal-data)))
        )
      (begin
        ;; Execute based on proposal type
        (if (is-eq (get proposal-type proposal-data) PROPOSAL-TYPE-TREASURY)
          (match (map-get? treasury-proposals {proposal-id: proposal-id})
            treasury-data
            ;; Call governance contract for treasury payment
            (begin
              ;; Placeholder for actual execution
              (map-set proposals
                {proposal-id: proposal-id}
                (merge proposal-data {status: PROPOSAL-STATUS-EXECUTED})
              )
              (map-set proposal-executions
                {proposal-id: proposal-id}
                {
                  executed-by: tx-sender,
                  execution-timestamp: stacks-block-height,
                  execution-result: true,
                  gas-used: u0,
                  execution-notes: none
                }
              )
              (var-set proposals-executed (+ (var-get proposals-executed) u1))
              (ok true)
            )
            (err ERR-PROPOSAL-NOT-FOUND)
          )
          ;; Handle other proposal types
          (begin
            (map-set proposals
              {proposal-id: proposal-id}
              (merge proposal-data {status: PROPOSAL-STATUS-EXECUTED})
            )
            (var-set proposals-executed (+ (var-get proposals-executed) u1))
            (ok true)
          )
        )
      )
      (err ERR-EXECUTION-DELAY-NOT-MET)
    )
  )
)

;; Administrative Functions

(define-public (cancel-proposal (proposal-id uint))
  (let ((proposal-data (unwrap! (map-get? proposals {proposal-id: proposal-id}) (err ERR-PROPOSAL-NOT-FOUND))))
    (if (and
          (or (is-eq tx-sender (get proposer proposal-data)) (is-contract-owner tx-sender))
          (is-eq (get status proposal-data) PROPOSAL-STATUS-ACTIVE)
        )
      (begin
        (map-set proposals
          {proposal-id: proposal-id}
          (merge proposal-data {
            status: PROPOSAL-STATUS-CANCELLED
          })
        )
        (var-set active-proposals (- (var-get active-proposals) u1))
        (ok true)
      )
      (err ERR-CANNOT-CANCEL)
    )
  )
)

;; Read-only Functions

(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals {proposal-id: proposal-id})
)

(define-read-only (get-proposal-tally (proposal-id uint))
  (map-get? proposal-tallies {proposal-id: proposal-id})
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? proposal-votes {proposal-id: proposal-id, voter: voter})
)

(define-read-only (get-treasury-proposal (proposal-id uint))
  (map-get? treasury-proposals {proposal-id: proposal-id})
)

(define-read-only (get-parameter-proposal (proposal-id uint))
  (map-get? parameter-proposals {proposal-id: proposal-id})
)

(define-read-only (get-membership-proposal (proposal-id uint))
  (map-get? membership-proposals {proposal-id: proposal-id})
)

(define-read-only (get-proposal-execution (proposal-id uint))
  (map-get? proposal-executions {proposal-id: proposal-id})
)

(define-read-only (get-proposal-stats)
  {
    total-proposals: (var-get total-proposals),
    active-proposals: (var-get active-proposals),
    proposals-executed: (var-get proposals-executed),
    emergency-proposals: (var-get emergency-proposals-count)
  }
)

(define-read-only (has-voted (proposal-id uint) (voter principal))
  (is-some (map-get? proposal-votes {proposal-id: proposal-id, voter: voter}))
)

(define-read-only (get-proposal-outcome (proposal-id uint))
  (calculate-vote-outcome proposal-id)
)


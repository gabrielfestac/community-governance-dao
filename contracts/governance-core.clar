;; Governance Core Contract
;; DAO membership, voting power, treasury management, and core governance mechanisms
;; Provides comprehensive framework for decentralized autonomous organization operations

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u3001))
(define-constant ERR-ALREADY-MEMBER (err u3002))
(define-constant ERR-NOT-MEMBER (err u3003))
(define-constant ERR-INSUFFICIENT-STAKE (err u3004))
(define-constant ERR-INVALID-AMOUNT (err u3005))
(define-constant ERR-INSUFFICIENT-TREASURY (err u3006))
(define-constant ERR-MEMBER-SUSPENDED (err u3007))
(define-constant ERR-INVALID-DELEGATION (err u3008))
(define-constant ERR-TREASURY-LOCKED (err u3009))
(define-constant ERR-INVALID-THRESHOLD (err u3010))
(define-constant ERR-PARAMETER-LOCKED (err u3011))
(define-constant ERR-EMERGENCY-ACTIVE (err u3012))
(define-constant ERR-INSUFFICIENT-VOTING-POWER (err u3013))
(define-constant ERR-INVALID-MEMBER-STATUS (err u3014))
(define-constant ERR-DELEGATION-CYCLE (err u3015))

;; Member Status Constants
(define-constant MEMBER-STATUS-PENDING "pending")
(define-constant MEMBER-STATUS-ACTIVE "active")
(define-constant MEMBER-STATUS-SUSPENDED "suspended")
(define-constant MEMBER-STATUS-INACTIVE "inactive")
(define-constant MEMBER-STATUS-EXPELLED "expelled")

;; Treasury Operations
(define-constant TREASURY-OP-DEPOSIT "deposit")
(define-constant TREASURY-OP-WITHDRAWAL "withdrawal")
(define-constant TREASURY-OP-PAYMENT "payment")
(define-constant TREASURY-OP-INVESTMENT "investment")

;; Governance Parameters
(define-constant MIN-STAKE-AMOUNT u1000000) ;; 1 STX minimum stake
(define-constant MIN-PROPOSAL-THRESHOLD u5) ;; 5% of total voting power
(define-constant DEFAULT-VOTING-PERIOD u1440) ;; 1440 blocks (~1 week)
(define-constant DEFAULT-EXECUTION-DELAY u720) ;; 720 blocks (~3.5 days)
(define-constant DEFAULT-QUORUM u20) ;; 20% participation required

;; Data Variables
(define-data-var dao-name (string-ascii 100) "Community DAO")
(define-data-var total-members uint u0)
(define-data-var total-voting-power uint u0)
(define-data-var treasury-balance uint u0)
(define-data-var emergency-mode bool false)
(define-data-var next-member-id uint u1)
(define-data-var governance-token principal tx-sender)

;; Governance Parameters (adjustable through proposals)
(define-data-var min-stake-amount uint MIN-STAKE-AMOUNT)
(define-data-var proposal-threshold uint MIN-PROPOSAL-THRESHOLD)
(define-data-var voting-period uint DEFAULT-VOTING-PERIOD)
(define-data-var execution-delay uint DEFAULT-EXECUTION-DELAY)
(define-data-var quorum-requirement uint DEFAULT-QUORUM)
(define-data-var parameter-update-delay uint u720)

;; Data Maps

;; DAO Members Registry
(define-map dao-members
  { member: principal }
  {
    member-id: uint,
    status: (string-ascii 20),
    stake-amount: uint,
    voting-power: uint,
    delegated-power: uint,
    delegate: (optional principal),
    join-date: uint,
    last-activity: uint,
    proposal-count: uint,
    vote-count: uint,
    reputation-score: uint
  }
)

;; Member Delegations
(define-map member-delegations
  { delegator: principal }
  {
    delegate: principal,
    voting-power-delegated: uint,
    delegation-date: uint,
    active: bool
  }
)

;; Delegation Received (for delegates)
(define-map delegation-received
  { delegate: principal }
  {
    total-delegated-power: uint,
    delegator-count: uint,
    last-updated: uint
  }
)

;; Treasury Operations Log
(define-map treasury-operations
  { operation-id: uint }
  {
    operation-type: (string-ascii 20),
    amount: uint,
    recipient: (optional principal),
    sender: (optional principal),
    description: (string-ascii 200),
    block-height: uint,
    authorized-by: principal
  }
)

;; Member Rewards and Penalties
(define-map member-rewards
  { member: principal, period: uint }
  {
    governance-rewards: uint,
    participation-bonus: uint,
    penalty-amount: uint,
    net-reward: int,
    claimed: bool,
    claim-date: (optional uint)
  }
)

;; Governance Parameter History
(define-map parameter-history
  { parameter: (string-ascii 50), change-id: uint }
  {
    old-value: uint,
    new-value: uint,
    changed-by: principal,
    change-date: uint,
    effective-date: uint
  }
)

;; Emergency Powers
(define-map emergency-powers
  { holder: principal }
  {
    granted-by: principal,
    granted-at: uint,
    expires-at: uint,
    powers: (string-ascii 200),
    active: bool
  }
)

;; Treasury Budgets
(define-map treasury-budgets
  { category: (string-ascii 50), period: uint }
  {
    allocated-amount: uint,
    spent-amount: uint,
    remaining-amount: uint,
    approved-by: uint, ;; proposal ID
    start-block: uint,
    end-block: uint
  }
)

;; Private Functions

(define-private (is-contract-owner (caller principal))
  (is-eq caller CONTRACT-OWNER)
)

(define-private (is-member (member principal))
  (is-some (map-get? dao-members {member: member}))
)

(define-private (is-active-member (member principal))
  (match (map-get? dao-members {member: member})
    member-data
    (is-eq (get status member-data) MEMBER-STATUS-ACTIVE)
    false
  )
)

(define-private (calculate-voting-power (stake-amount uint))
  ;; Simple linear voting power based on stake
  ;; Can be enhanced with more sophisticated algorithms
  (/ (* stake-amount u100) MIN-STAKE-AMOUNT)
)

(define-private (update-member-activity (member principal))
  (match (map-get? dao-members {member: member})
    member-data
    (map-set dao-members
      {member: member}
      (merge member-data {
        last-activity: stacks-block-height
      })
    )
    false
  )
)

(define-private (validate-delegation (delegator principal) (delegate principal))
  ;; Prevent delegation cycles and self-delegation
  (and 
    (not (is-eq delegator delegate))
    (is-active-member delegate)
    ;; Additional cycle detection would be implemented here
    true
  )
)

(define-private (update-total-voting-power (change int))
  (let ((current-power (var-get total-voting-power)))
    (if (>= (to-int current-power) (- 0 change))
      (var-set total-voting-power (if (< change 0) 
                                    (- current-power (to-uint (- 0 change)))
                                    (+ current-power (to-uint change))))
      false
    )
  )
)

;; Public Functions

;; Member Management

(define-public (join-dao (stake-amount uint))
  (let ((member-id (var-get next-member-id))
        (voting-power (calculate-voting-power stake-amount)))
    (if (and
          (not (is-member tx-sender))
          (>= stake-amount (var-get min-stake-amount))
          (not (var-get emergency-mode))
        )
      (begin
        ;; In a full implementation, STX transfer would be handled here
        (map-set dao-members
          {member: tx-sender}
          {
            member-id: member-id,
            status: MEMBER-STATUS-ACTIVE,
            stake-amount: stake-amount,
            voting-power: voting-power,
            delegated-power: u0,
            delegate: none,
            join-date: stacks-block-height,
            last-activity: stacks-block-height,
            proposal-count: u0,
            vote-count: u0,
            reputation-score: u100
          }
        )
        (var-set next-member-id (+ member-id u1))
        (var-set total-members (+ (var-get total-members) u1))
        (update-total-voting-power (to-int voting-power))
        (ok member-id)
      )
      (err ERR-ALREADY-MEMBER)
    )
  )
)

(define-public (increase-stake (additional-stake uint))
  (let ((member-data (unwrap! (map-get? dao-members {member: tx-sender}) (err ERR-NOT-MEMBER)))
        (new-stake (+ (get stake-amount member-data) additional-stake))
        (new-voting-power (calculate-voting-power new-stake))
        (power-increase (- new-voting-power (get voting-power member-data))))
    (if (and
          (is-active-member tx-sender)
          (> additional-stake u0)
        )
      (begin
        (map-set dao-members
          {member: tx-sender}
          (merge member-data {
            stake-amount: new-stake,
            voting-power: new-voting-power,
            last-activity: stacks-block-height
          })
        )
        (update-total-voting-power (to-int power-increase))
        (ok new-voting-power)
      )
      (err ERR-NOT-MEMBER)
    )
  )
)

(define-public (delegate-voting-power (delegate principal))
  (let ((member-data (unwrap! (map-get? dao-members {member: tx-sender}) (err ERR-NOT-MEMBER)))
        (current-delegation (map-get? member-delegations {delegator: tx-sender})))
    (if (and
          (is-active-member tx-sender)
          (validate-delegation tx-sender delegate)
        )
      (begin
        ;; Remove existing delegation if any
        (match current-delegation
          existing-del
          (begin
            (map-delete member-delegations {delegator: tx-sender})
            ;; Update previous delegate's received delegations
            (match (map-get? delegation-received {delegate: (get delegate existing-del)})
              prev-received
              (map-set delegation-received
                {delegate: (get delegate existing-del)}
                (merge prev-received {
                  total-delegated-power: (- (get total-delegated-power prev-received) (get voting-power-delegated existing-del)),
                  delegator-count: (- (get delegator-count prev-received) u1)
                })
              )
              true
            )
          )
          true
        )
        
        ;; Create new delegation
        (map-set member-delegations
          {delegator: tx-sender}
          {
            delegate: delegate,
            voting-power-delegated: (get voting-power member-data),
            delegation-date: stacks-block-height,
            active: true
          }
        )
        
        ;; Update delegate's received delegations
        (match (map-get? delegation-received {delegate: delegate})
          received-data
          (map-set delegation-received
            {delegate: delegate}
            (merge received-data {
              total-delegated-power: (+ (get total-delegated-power received-data) (get voting-power member-data)),
              delegator-count: (+ (get delegator-count received-data) u1),
              last-updated: stacks-block-height
            })
          )
          (map-set delegation-received
            {delegate: delegate}
            {
              total-delegated-power: (get voting-power member-data),
              delegator-count: u1,
              last-updated: stacks-block-height
            }
          )
        )
        
        ;; Update member's delegate info
        (map-set dao-members
          {member: tx-sender}
          (merge member-data {
            delegate: (some delegate),
            last-activity: stacks-block-height
          })
        )
        
        (ok true)
      )
      (err ERR-INVALID-DELEGATION)
    )
  )
)

(define-public (revoke-delegation)
  (let ((current-delegation (unwrap! (map-get? member-delegations {delegator: tx-sender}) (err ERR-INVALID-DELEGATION)))
        (member-data (unwrap! (map-get? dao-members {member: tx-sender}) (err ERR-NOT-MEMBER))))
    (begin
      ;; Remove delegation
      (map-delete member-delegations {delegator: tx-sender})
      
      ;; Update delegate's received delegations
      (match (map-get? delegation-received {delegate: (get delegate current-delegation)})
        received-data
        (map-set delegation-received
          {delegate: (get delegate current-delegation)}
          (merge received-data {
            total-delegated-power: (- (get total-delegated-power received-data) (get voting-power-delegated current-delegation)),
            delegator-count: (- (get delegator-count received-data) u1),
            last-updated: stacks-block-height
          })
        )
        true
      )
      
      ;; Update member info
      (map-set dao-members
        {member: tx-sender}
        (merge member-data {
          delegate: none,
          last-activity: stacks-block-height
        })
      )
      
      (ok true)
    )
  )
)

;; Treasury Management

(define-public (deposit-to-treasury (amount uint) (description (string-ascii 200)))
  (if (and
        (is-active-member tx-sender)
        (> amount u0)
      )
    (begin
      ;; In a full implementation, STX transfer would be handled here
      (var-set treasury-balance (+ (var-get treasury-balance) amount))
      ;; Log treasury operation would be implemented here
      (ok (var-get treasury-balance))
    )
    (err ERR-NOT-AUTHORIZED)
  )
)

(define-public (treasury-payment (recipient principal) (amount uint) (description (string-ascii 200)))
  ;; This would typically be called through a proposal execution
  (if (and
        (is-contract-owner tx-sender) ;; In practice, this would be proposal contract
        (>= (var-get treasury-balance) amount)
      )
    (begin
      (var-set treasury-balance (- (var-get treasury-balance) amount))
      ;; STX transfer would be implemented here
      ;; Log operation would be implemented here
      (ok true)
    )
    (err ERR-INSUFFICIENT-TREASURY)
  )
)

;; Governance Parameter Management

(define-public (update-governance-parameter (parameter (string-ascii 50)) (new-value uint))
  ;; This would typically be called through proposal execution
  (if (is-contract-owner tx-sender) ;; In practice, this would be proposal contract
    (begin
      (if (is-eq parameter "min-stake-amount")
        (var-set min-stake-amount new-value)
        (if (is-eq parameter "proposal-threshold")
          (var-set proposal-threshold new-value)
          (if (is-eq parameter "voting-period")
            (var-set voting-period new-value)
            (if (is-eq parameter "execution-delay")
              (var-set execution-delay new-value)
              (if (is-eq parameter "quorum-requirement")
                (var-set quorum-requirement new-value)
                false
              )
            )
          )
        )
      )
      (ok true)
    )
    (err ERR-NOT-AUTHORIZED)
  )
)

;; Emergency Functions

(define-public (activate-emergency-mode)
  (if (is-contract-owner tx-sender)
    (begin
      (var-set emergency-mode true)
      (ok true)
    )
    (err ERR-NOT-AUTHORIZED)
  )
)

(define-public (deactivate-emergency-mode)
  (if (is-contract-owner tx-sender)
    (begin
      (var-set emergency-mode false)
      (ok true)
    )
    (err ERR-NOT-AUTHORIZED)
  )
)

;; Read-only Functions

(define-read-only (get-member-info (member principal))
  (map-get? dao-members {member: member})
)

(define-read-only (get-member-voting-power (member principal))
  (match (map-get? dao-members {member: member})
    member-data
    (some (+ (get voting-power member-data)
             (default-to u0 (get total-delegated-power (map-get? delegation-received {delegate: member})))))
    none
  )
)

(define-read-only (get-delegation-info (delegator principal))
  (map-get? member-delegations {delegator: delegator})
)

(define-read-only (get-received-delegations (delegate principal))
  (map-get? delegation-received {delegate: delegate})
)

(define-read-only (get-dao-stats)
  {
    name: (var-get dao-name),
    total-members: (var-get total-members),
    total-voting-power: (var-get total-voting-power),
    treasury-balance: (var-get treasury-balance),
    emergency-mode: (var-get emergency-mode)
  }
)

(define-read-only (get-governance-parameters)
  {
    min-stake-amount: (var-get min-stake-amount),
    proposal-threshold: (var-get proposal-threshold),
    voting-period: (var-get voting-period),
    execution-delay: (var-get execution-delay),
    quorum-requirement: (var-get quorum-requirement)
  }
)

(define-read-only (is-member-active (member principal))
  (is-active-member member)
)


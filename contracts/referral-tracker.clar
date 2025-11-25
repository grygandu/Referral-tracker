;; ============================================================
;; referral-tracker
;; On-chain referral tracking system
;; ============================================================

(define-data-var admin principal tx-sender)
(define-data-var reward-enabled bool false)
(define-data-var reward-amount uint u0)

(define-constant ERR-NOT-AUTHORIZED u100)
(define-constant ERR-ALREADY-REFERRED u101)
(define-constant ERR-INVALID-REFERRER u102)
(define-constant ERR-CANNOT-SELF-REFER u103)
(define-constant ERR-NO-REWARD u104)

;; ------------------------------------------------------------
;; Data Structures
;; ------------------------------------------------------------
(define-map referrers
  { user: principal }
  {
    total-referrals: uint,
    total-rewards: uint
  }
)

(define-map referred-by
  { user: principal }
  principal
)

;; ------------------------------------------------------------
;; Read-Only Views
;; ------------------------------------------------------------
(define-read-only (is-referrer (user principal))
  (is-some (map-get? referrers { user: user }))
)

(define-read-only (has-referrer (user principal))
  (is-some (map-get? referred-by { user: user }))
)

;; ------------------------------------------------------------
;; Admin Functions
;; ------------------------------------------------------------
(define-public (set-reward-enabled (flag bool))
  (if (is-eq tx-sender (var-get admin))
      (begin
        (var-set reward-enabled flag)
        (ok true))
      (err ERR-NOT-AUTHORIZED))
)

(define-public (set-reward-amount (amount uint))
  (if (is-eq tx-sender (var-get admin))
      (begin
        (var-set reward-amount amount)
        (ok true))
      (err ERR-NOT-AUTHORIZED))
)

(define-public (withdraw (amount uint) (recipient principal))
  (if (is-eq tx-sender (var-get admin))
      (stx-transfer? amount tx-sender recipient)
      (err ERR-NOT-AUTHORIZED))
)

;; ------------------------------------------------------------
;; User Functions
;; ------------------------------------------------------------
(define-public (register-referrer)
  ;; Fixed type mismatch by ensuring both branches return a response
  (if (is-referrer tx-sender)
      (ok false) ;; already registered
      (begin
        (map-set referrers
          { user: tx-sender }
          {
            total-referrals: u0,
            total-rewards: u0
          })
        (ok true)))
)

(define-public (submit-referral (referrer principal))
  (begin
    ;; Replaced if checks with asserts! to handle intermediate responses
    (asserts! (not (is-eq tx-sender referrer)) (err ERR-CANNOT-SELF-REFER))
    (asserts! (not (has-referrer tx-sender)) (err ERR-ALREADY-REFERRED))
    (asserts! (is-referrer referrer) (err ERR-INVALID-REFERRER))

    ;; record referral
    (map-set referred-by { user: tx-sender } referrer)

    ;; update referral count
    (let (
          (r (unwrap! (map-get? referrers { user: referrer })
                      (err ERR-INVALID-REFERRER)))
         )
      (map-set referrers
        { user: referrer }
        (merge r {
          ;; Fixed dot notation to use (get ...)
          total-referrals: (+ (get total-referrals r) u1)
        }))
    )

    ;; send reward if enabled
    (if (var-get reward-enabled)
        (begin
          ;; Added try! to check stx-transfer? response
          (try! (stx-transfer? (var-get reward-amount) tx-sender referrer))
          (let (
                (r2 (unwrap! (map-get? referrers { user: referrer })
                             (err ERR-INVALID-REFERRER)))
               )
            (map-set referrers
              { user: referrer }
              (merge r2 {
                ;; Fixed dot notation to use (get ...)
                total-rewards: (+ (get total-rewards r2) (var-get reward-amount))
              }))
          )
          (ok true)
        )
        (ok true)
    )
  )
)

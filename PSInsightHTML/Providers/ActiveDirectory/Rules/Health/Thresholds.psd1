@{
    Version = '1.0'
    Source = 'Provider-defined operational threshold; review for the assessed environment'
    DiskCriticalFreeGB = 10
    DiskReviewFreeGB = 15
    MemoryReviewPercent = 90
    CpuReviewPercent = 85
    UptimeReviewDays = 180
    TimeOffsetReviewMilliseconds = 100
    ReplicationCriticalConsecutiveFailures = 3
    ReplicationCriticalStaleMinutes = 180
    BackupHealthyDays = 1
    BackupCriticalDays = 3
    ReadyScoreMinimum = 90
    ReviewScoreMinimum = 75
}

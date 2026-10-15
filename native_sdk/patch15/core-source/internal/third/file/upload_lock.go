package file

import "context"

// Count the owner and waiters under mapLocker so cancelled waiters never delete
// a lock still held by another upload of the same content.
type lockInfo struct {
	count int
	token chan struct{}
}

func (f *File) lockHash(ctx context.Context, hash string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	f.mapLocker.Lock()
	lock := f.uploading[hash]
	if lock == nil {
		lock = &lockInfo{token: make(chan struct{}, 1)}
		f.uploading[hash] = lock
	}
	lock.count++
	f.mapLocker.Unlock()
	select {
	case lock.token <- struct{}{}:
		if err := ctx.Err(); err != nil {
			f.unlockHash(hash)
			return err
		}
		return nil
	case <-ctx.Done():
		f.releaseHash(hash, false)
		return ctx.Err()
	}
}

func (f *File) unlockHash(hash string) { f.releaseHash(hash, true) }

func (f *File) releaseHash(hash string, acquired bool) {
	f.mapLocker.Lock()
	defer f.mapLocker.Unlock()
	lock := f.uploading[hash]
	if lock == nil {
		return
	}
	if acquired {
		<-lock.token
	}
	lock.count--
	if lock.count == 0 {
		delete(f.uploading, hash)
	}
}

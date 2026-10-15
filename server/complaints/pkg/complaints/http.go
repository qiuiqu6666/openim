package complaints

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/openimsdk/chat/pkg/feedback"
	"github.com/openimsdk/tools/apiresp"
	"github.com/openimsdk/tools/errs"
	"github.com/redis/go-redis/v9"
	"io"
	"net/http"
	"strconv"
	"time"
)

type Media interface {
	PutKey(context.Context, string, string, []byte) error
	RemoveKey(context.Context, string) error
	Read(context.Context, string, int64) ([]byte, error)
}
type API struct {
	Enrich   func(context.Context, []*Record) error
	Store    *Store
	Media    Media
	Redis    redis.UniversalClient
	Validate func(context.Context, string, *Payload, string) error
}

func (a *API) Create(c *gin.Context, owner, chatType string) {
	fail := func(err error) { apiresp.GinError(c, err) }
	// Atomic per-user lock also protects concurrent retries and object cleanup.
	key := "complaint:lock:" + owner
	lock := uuid.NewString()
	ok, err := a.Redis.SetNX(c, key, lock, 2*time.Minute).Result()
	if err != nil {
		fail(err)
		return
	}
	if !ok {
		fail(ErrRate.WrapMsg("complaint submission in progress"))
		return
	}
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		_ = a.Redis.Eval(ctx, `if redis.call('get',KEYS[1])==ARGV[1] then return redis.call('del',KEYS[1]) end return 0`, []string{key}, lock).Err()
	}()
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 5*feedback.MaxImageBytes+(1<<20))
	var p Payload
	type upload struct {
		body       []byte
		mime, hash string
	}
	shots := []upload{}
	hashes := []string{}
	if err = c.Request.ParseMultipartForm(4 << 20); err != nil {
		fail(errs.ErrArgs.WrapMsg("invalid multipart"))
		return
	}
	if c.Request.MultipartForm == nil {
		fail(errs.ErrArgs.WrapMsg("multipart required"))
		return
	}
	defer c.Request.MultipartForm.RemoveAll()
	if err = json.Unmarshal([]byte(c.PostForm("payload")), &p); err != nil {
		fail(errs.ErrArgs.WrapMsg("invalid payload"))
		return
	}
	p, err = Normalize(p, chatType, owner)
	if err != nil {
		fail(err)
		return
	}
	headers := c.Request.MultipartForm.File["screenshots"]
	if len(headers) > 5 {
		fail(errs.ErrArgs.WrapMsg("too many screenshots"))
		return
	}
	for _, h := range headers {
		f, e := h.Open()
		if e != nil {
			fail(e)
			return
		}
		b, e := io.ReadAll(io.LimitReader(f, feedback.MaxImageBytes+1))
		f.Close()
		if e != nil {
			fail(e)
			return
		}
		mime, hash, e := feedback.InspectScreenshot(b)
		if e != nil {
			fail(e)
			return
		}
		shots = append(shots, upload{b, mime, hash})
		hashes = append(hashes, hash)
	}
	digest := Digest(p, chatType, hashes)
	old, err := a.Store.Replay(c, owner, p.ClientRequestID, digest)
	if err != nil {
		fail(err)
		return
	}
	if old != nil {
		apiresp.GinSuccess(c, old)
		return
	}
	// Count attempts before validation/storage so invalid traffic is bounded too.
	n, err := a.Redis.Eval(c, `local n=redis.call('incr',KEYS[1]);if n==1 then redis.call('expire',KEYS[1],600) end return n`, []string{"complaint:rate:" + owner}).Int()
	if err != nil {
		fail(err)
		return
	}
	if n > 10 {
		fail(ErrRate.WrapMsg("too many complaints; try later"))
		return
	}
	if err = a.Validate(c, owner, &p, chatType); err != nil {
		fail(err)
		return
	}
	row := &Record{Payload: p, UserID: owner, ChatType: chatType, Digest: digest, Screenshots: []Shot{}}
	keys := []string{}
	committed := false
	defer func() {
		if !committed {
			ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
			defer cancel()
			for _, key := range keys {
				_ = a.Media.RemoveKey(ctx, key)
			}
		}
	}()
	batch := uuid.NewString()
	for i, s := range shots {
		key := "complaints/" + batch + "/" + strconv.Itoa(i)
		keys = append(keys, key)
		if err = a.Media.PutKey(c, key, s.mime, s.body); err != nil {
			fail(err)
			return
		}
		row.Screenshots = append(row.Screenshots, Shot{Key: key, Mime: s.mime, Size: int64(len(s.body))})
	}
	saved, err := a.Store.Insert(c, row)
	if err != nil {
		committed = true
		fail(err)
		return
	}
	// An ambiguous insert error is recovered on retry by the unique request key.
	committed = saved.ID == row.ID
	apiresp.GinSuccess(c, saved)
}
func (a *API) Search(c *gin.Context) {
	var q Search
	if err := c.ShouldBindJSON(&q); err != nil {
		apiresp.GinError(c, errs.ErrArgs)
		return
	}
	rows, total, err := a.Store.Search(c, q)
	if err != nil {
		apiresp.GinError(c, err)
		return
	}
	if a.Enrich != nil {
		refs := make([]*Record, len(rows))
		for i := range rows {
			refs[i] = &rows[i]
		}
		if err := a.Enrich(c, refs); err != nil {
			apiresp.GinError(c, err)
			return
		}
	}
	apiresp.GinSuccess(c, gin.H{"complaints": rows, "total": total})
}
func (a *API) Detail(c *gin.Context) {
	var q struct {
		ID string `json:"complaintID" binding:"required"`
	}
	if err := c.ShouldBindJSON(&q); err != nil {
		apiresp.GinError(c, errs.ErrArgs)
		return
	}
	row, err := a.Store.Detail(c, q.ID)
	if err != nil {
		apiresp.GinError(c, errs.ErrRecordNotFound)
		return
	}
	if a.Enrich != nil {
		if err := a.Enrich(c, []*Record{row}); err != nil {
			apiresp.GinError(c, err)
			return
		}
	}
	apiresp.GinSuccess(c, row)
}
func (a *API) Update(c *gin.Context, admin string) {
	var q struct {
		ID     string `json:"complaintID" binding:"required"`
		Status string `json:"status"`
		Note   string `json:"note"`
	}
	if err := c.ShouldBindJSON(&q); err != nil {
		apiresp.GinError(c, errs.ErrArgs)
		return
	}
	row, err := a.Store.Update(c, q.ID, q.Status, q.Note, admin)
	if err != nil {
		apiresp.GinError(c, err)
		return
	}
	if a.Enrich != nil {
		if err := a.Enrich(c, []*Record{row}); err != nil {
			apiresp.GinError(c, err)
			return
		}
	}
	apiresp.GinSuccess(c, row)
}

func (a *API) Screenshot(c *gin.Context) {
	var q struct {
		ID    string `json:"complaintID" binding:"required"`
		Index int    `json:"index"`
	}
	if err := c.ShouldBindJSON(&q); err != nil {
		apiresp.GinError(c, errs.ErrArgs)
		return
	}
	row, err := a.Store.Detail(c, q.ID)
	if err != nil {
		apiresp.GinError(c, errs.ErrRecordNotFound)
		return
	}
	if q.Index < 0 || q.Index >= len(row.Screenshots) {
		apiresp.GinError(c, errs.ErrArgs)
		return
	}
	shot := row.Screenshots[q.Index]
	body, err := a.Media.Read(c, shot.Key, feedback.MaxImageBytes)
	if err != nil {
		apiresp.GinError(c, err)
		return
	}
	c.Header("Cache-Control", "no-store")
	c.Header("X-Content-Type-Options", "nosniff")
	c.Header("Content-Disposition", fmt.Sprintf("inline; filename=screenshot-%d", q.Index+1))
	c.Data(200, shot.Mime, body)
}

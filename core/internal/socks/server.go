package socks

import (
	"context"
	"fmt"
	"io"
	"log"
	"net"
	"strings"
	"sync"
	"time"

	"github.com/kianmhz/GooseRelayVPN/internal/session"
	"github.com/things-go/go-socks5"
	"github.com/things-go/go-socks5/statute"
	"golang.org/x/net/dns/dnsmessage"
)

var (
	dnsCache   = make(map[string]string)
	dnsCacheMu sync.RWMutex
)

func cacheDNS(ip, domain string) {
	dnsCacheMu.Lock()
	defer dnsCacheMu.Unlock()
	if len(dnsCache) > 5000 {
		dnsCache = make(map[string]string)
	}
	dnsCache[ip] = domain
}

func parseAndCacheDNSResponse(resp []byte) {
	var p dnsmessage.Parser
	header, err := p.Start(resp)
	if err != nil {
		return
	}
	_ = header
	for {
		_, err := p.Question()
		if err != nil {
			break
		}
	}
	for {
		h, err := p.AnswerHeader()
		if err != nil {
			break
		}
		domain := h.Name.String()
		if len(domain) > 0 && domain[len(domain)-1] == '.' {
			domain = domain[:len(domain)-1]
		}
		switch h.Type {
		case dnsmessage.TypeA:
			res, err := p.AResource()
			if err == nil {
				ip := net.IP(res.A[:]).String()
				cacheDNS(ip, domain)
			}
		case dnsmessage.TypeAAAA:
			res, err := p.AAAAResource()
			if err == nil {
				ip := net.IP(res.AAAA[:]).String()
				cacheDNS(ip, domain)
			}
		default:
			if err := p.SkipAnswer(); err != nil {
				break
			}
		}
	}
}

func shouldBypass(addr string) bool {
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		host = addr
	}

	ip := net.ParseIP(host)
	if ip != nil {
		if ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() {
			return true
		}
		dnsCacheMu.RLock()
		domain, found := dnsCache[ip.String()]
		dnsCacheMu.RUnlock()
		if found {
			host = domain
		}
	}

	host = strings.ToLower(host)
	if strings.HasSuffix(host, ".ir") {
		return true
	}

	bypassKeywords := []string{
		"snapp", "digikala", "divar", "cafebazaar", "bazaar", "myket", "tapsi", "filimo",
		"namava", "aparat", "telewebion", "shad", "splus", "rubika", "eitaa", "bale",
		"sanjesh", "irandoc", "medu", "melli", "tejarat", "mellat", "saderat", "sepah",
		"refah", "keshavarzi", "pasargad", "parsian", "saman", "karafarin", "sina",
		"shahr", "maskan", "asanpardakht", "zarinpal", "shaparak", "alibaba", "flytoday",
		"snapptrip", "jabama", "ostadkar", "achareh", "fidibo", "taaghche", "digiato",
		"zoomit", "varzesh3", "tasnimnews", "farsnews", "isna", "irna", "mehrnews",
		"yjc", "hamshahri", "keyhan", "etelaat", "donya-e-eqtesad", "tgju", "mesghal",
	}

	for _, kw := range bypassKeywords {
		if strings.Contains(host, kw) {
			return true
		}
	}

	return false
}

// SessionFactory creates a new tunneled session for the given "host:port"
// target. The returned session is owned by the carrier (which polls it for
// outgoing frames and routes incoming ones).
type SessionFactory func(target string) *session.Session

// Serve starts a SOCKS5 listener on listenAddr that wraps every connection in
// a VirtualConn over a fresh tunneled session. The DNS resolver is overridden
// with a no-op to prevent local DNS leaks (clients must use socks5h://).
//
// Wraps the listener with a TCP_NODELAY + TCP_QUICKACK applying acceptor so
// the kernel doesn't introduce 40 ms Nagle delays on small SOCKS payloads
// (HTTP request lines, TLS handshake records) and doesn't hold back ACKs for
// up to 40 ms on small request/reply pairs. The exit side already disables
// Nagle for upstream connections; mirroring on the local side closes the loop.
//
// When user and pass are both non-empty, RFC 1929 username/password
// authentication is required; unauthenticated clients are rejected.
//
// Blocks until ListenAndServe returns. Caller passes ctx for shutdown
// signaling (the underlying go-socks5 library doesn't take a ctx, so this
// just wires it through for parity with the rest of the codebase).
func Serve(_ context.Context, listenAddr, user, pass string, debugTiming bool, factory SessionFactory) error {
	opts := []socks5.Option{
		socks5.WithDial(func(ctx context.Context, _, addr string) (net.Conn, error) {
			if shouldBypass(addr) {
				if debugTiming {
					log.Printf("[socks] bypassing tunnel (direct dial) for %s", addr)
				}
				dialer := &net.Dialer{Timeout: 5 * time.Second}
				return dialer.DialContext(ctx, "tcp", addr)
			}
			s := factory(addr)
			if s == nil {
				return nil, fmt.Errorf("VPN tunnel is closed")
			}
			if debugTiming {
				log.Printf("[socks] new session %x for %s", s.ID[:4], addr)
			}
			return NewVirtualConn(s), nil
		}),
		socks5.WithAssociateHandle(func(ctx context.Context, w io.Writer, req *socks5.Request) error {
			conn, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 0})
			if err != nil {
				_ = socks5.SendReply(w, statute.RepServerFailure, nil)
				return err
			}
			localAddr := conn.LocalAddr().(*net.UDPAddr)

			err = socks5.SendReply(w, statute.RepSuccess, localAddr)
			if err != nil {
				conn.Close()
				return err
			}

			// Handle UDP relay
			go func() {
				buf := make([]byte, 65535)
				for {
					n, clientAddr, err := conn.ReadFrom(buf)
					if err != nil {
						break
					}

					headerLen, destAddr, err := parseUDPHeader(buf[:n])
					if err != nil {
						continue
					}

					_, portStr, _ := net.SplitHostPort(destAddr)
					if portStr != "53" {
						continue // Only DNS is supported
					}

					payload := make([]byte, n-headerLen)
					copy(payload, buf[headerLen:n])

					go func(dest string, client net.Addr, dnsQuery []byte) {
						dialTunnel := func(ctx context.Context, network, addr string) (net.Conn, error) {
							s := factory(addr)
							if s == nil {
								return nil, fmt.Errorf("VPN tunnel is closed")
							}
							return NewVirtualConn(s), nil
						}
						resp, err := resolveDNSOverTCP(ctx, dialTunnel, dest, dnsQuery)
						if err != nil {
							if debugTiming {
								log.Printf("[socks] DNS resolve over TCP error for %s: %v", dest, err)
							}
							return
						}

						parseAndCacheDNSResponse(resp)

						header, err := makeUDPHeader(dest)
						if err != nil {
							return
						}

						respPacket := append(header, resp...)
						_, _ = conn.WriteTo(respPacket, client)
					}(destAddr, clientAddr, payload)
				}
			}()

			// Wait for TCP connection to close
			buf := make([]byte, 1)
			for {
				_, err := req.Reader.Read(buf)
				if err != nil {
					break
				}
			}
			conn.Close()
			return nil
		}),
		socks5.WithResolver(noopResolver{}),
	}
	if user != "" {
		opts = append(opts, socks5.WithAuthMethods([]socks5.Authenticator{
			socks5.UserPassAuthenticator{
				Credentials: socks5.StaticCredentials{user: pass},
			},
		}))
	}

	ln, err := net.Listen(listenNetwork(listenAddr), listenAddr)
	if err != nil {
		return err
	}
	server := socks5.NewServer(opts...)
	return server.Serve(&noDelayListener{Listener: ln})
}

// listenNetwork picks the right network family for net.Listen based on the
// literal address. Defaulting to "tcp" causes Go to bind an AF_INET6 socket
// with V4MAPPED even for explicit IPv4 addresses like "0.0.0.0"; on Linux
// hosts where net.ipv6.bindv6only=1, that socket then refuses IPv4
// connections (issues #94 and #111). Forcing "tcp4" / "tcp6" when the host
// is an IP literal sidesteps that, while leaving hostnames on "tcp" so
// resolver-driven setups (e.g. "localhost") still work.
func listenNetwork(addr string) string {
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		return "tcp"
	}
	if host == "" {
		return "tcp" // bare ":1080" — let Go pick
	}
	ip := net.ParseIP(host)
	if ip == nil {
		return "tcp"
	}
	if ip.To4() != nil {
		return "tcp4"
	}
	return "tcp6"
}

// noDelayListener wraps net.Listener so each accepted *net.TCPConn has both
// SetNoDelay(true) and (on Linux) TCP_QUICKACK applied. This eliminates the
// kernel's 40 ms Nagle delay on small SOCKS write payloads and the 40 ms
// delayed-ACK on small read replies — together they cover both directions
// of every interactive request/reply pair (DNS-over-HTTPS, REST GETs, TLS
// handshake records).
type noDelayListener struct {
	net.Listener
}

func (l *noDelayListener) Accept() (net.Conn, error) {
	c, err := l.Listener.Accept()
	if err != nil {
		return nil, err
	}
	if tcp, ok := c.(*net.TCPConn); ok {
		_ = tcp.SetNoDelay(true)
	}
	setQuickAck(c)
	return c, nil
}

// noopResolver is a SOCKS5 name resolver that returns the host string verbatim
// (no DNS lookup). Combined with socks5h:// clients, this keeps DNS off the
// local machine entirely — it's resolved on the VPS exit instead.
type noopResolver struct{}

func (noopResolver) Resolve(ctx context.Context, _ string) (context.Context, net.IP, error) {
	return ctx, nil, nil
}

func parseUDPHeader(data []byte) (headerLen int, destAddr string, err error) {
	if len(data) < 4 {
		return 0, "", fmt.Errorf("packet too short")
	}
	// RSV := data[0:2]
	// FRAG := data[2]
	atyp := data[3]
	switch atyp {
	case 0x01: // IPv4
		if len(data) < 10 {
			return 0, "", fmt.Errorf("IPv4 packet too short")
		}
		ip := net.IP(data[4:8])
		port := uint16(data[8])<<8 | uint16(data[9])
		return 10, fmt.Sprintf("%s:%d", ip.String(), port), nil
	case 0x03: // Domain name
		if len(data) < 5 {
			return 0, "", fmt.Errorf("domain packet too short")
		}
		addrLen := int(data[4])
		if len(data) < 5+addrLen+2 {
			return 0, "", fmt.Errorf("domain packet truncated")
		}
		domain := string(data[5 : 5+addrLen])
		port := uint16(data[5+addrLen])<<8 | uint16(data[5+addrLen+1])
		return 5 + addrLen + 2, fmt.Sprintf("%s:%d", domain, port), nil
	case 0x04: // IPv6
		if len(data) < 22 {
			return 0, "", fmt.Errorf("IPv6 packet too short")
		}
		ip := net.IP(data[4:20])
		port := uint16(data[20])<<8 | uint16(data[21])
		return 22, fmt.Sprintf("[%s]:%d", ip.String(), port), nil
	default:
		return 0, "", fmt.Errorf("unsupported ATYP: 0x%02x", atyp)
	}
}

func makeUDPHeader(destAddr string) ([]byte, error) {
	host, portStr, err := net.SplitHostPort(destAddr)
	if err != nil {
		return nil, err
	}
	var port uint16
	_, err = fmt.Sscan(portStr, &port)
	if err != nil {
		return nil, err
	}

	ip := net.ParseIP(host)
	if ip == nil {
		addrLen := len(host)
		if addrLen > 255 {
			return nil, fmt.Errorf("domain too long")
		}
		header := make([]byte, 5+addrLen+2)
		header[0] = 0x00
		header[1] = 0x00
		header[2] = 0x00
		header[3] = 0x03
		header[4] = byte(addrLen)
		copy(header[5:], host)
		header[5+addrLen] = byte(port >> 8)
		header[5+addrLen+1] = byte(port)
		return header, nil
	}

	if ip4 := ip.To4(); ip4 != nil {
		header := make([]byte, 10)
		header[0] = 0x00
		header[1] = 0x00
		header[2] = 0x00
		header[3] = 0x01
		copy(header[4:8], ip4)
		header[8] = byte(port >> 8)
		header[9] = byte(port)
		return header, nil
	}

	header := make([]byte, 22)
	header[0] = 0x00
	header[1] = 0x00
	header[2] = 0x00
	header[3] = 0x04
	copy(header[4:20], ip)
	header[20] = byte(port >> 8)
	header[21] = byte(port)
	return header, nil
}

func resolveDNSOverTCP(ctx context.Context, dial func(context.Context, string, string) (net.Conn, error), dnsAddr string, udpPayload []byte) ([]byte, error) {
	conn, err := dial(ctx, "tcp", dnsAddr)
	if err != nil {
		return nil, err
	}
	defer conn.Close()

	length := uint16(len(udpPayload))
	req := make([]byte, 2+len(udpPayload))
	req[0] = byte(length >> 8)
	req[1] = byte(length)
	copy(req[2:], udpPayload)

	if _, err := conn.Write(req); err != nil {
		return nil, err
	}

	lenBuf := make([]byte, 2)
	if _, err := io.ReadFull(conn, lenBuf); err != nil {
		return nil, err
	}
	respLen := int(uint16(lenBuf[0])<<8 | uint16(lenBuf[1]))

	respBuf := make([]byte, respLen)
	if _, err := io.ReadFull(conn, respBuf); err != nil {
		return nil, err
	}

	return respBuf, nil
}

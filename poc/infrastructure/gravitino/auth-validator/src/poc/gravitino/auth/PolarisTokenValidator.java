package poc.gravitino.auth;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwt;
import io.jsonwebtoken.Jwts;
import java.security.Key;
import java.security.KeyFactory;
import java.security.Principal;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;
import org.apache.gravitino.Config;
import org.apache.gravitino.UserPrincipal;
import org.apache.gravitino.exceptions.UnauthorizedException;
import org.apache.gravitino.server.authentication.OAuthConfig;
import org.apache.gravitino.server.authentication.OAuthTokenValidator;

/**
 * Spike-only OAuth validator for Polaris-issued JWTs.
 *
 * <p>Polaris' JWTBroker sets {@code iss=polaris}, {@code sub}, {@code active}, {@code scope} and
 * {@code polaris-cv}, but no {@code aud} claim. Gravitino's built-in StaticSignKeyValidator requires
 * an audience, so this validator verifies the RS256 signature, issuer and active flag only. The raw
 * Bearer token is attached to the UserPrincipal by OAuth2TokenAuthenticator and forwarded to Polaris
 * by UserPrincipalForwardingAuthManager.
 *
 * <p>This is a POC shim, not a production authentication design. Production should use an identity
 * provider/token broker that issues audience-bound tokens.
 */
public class PolarisTokenValidator implements OAuthTokenValidator {
  private static final String POLARIS_ISSUER = "polaris";
  private Key publicKey;

  @Override
  public void initialize(Config config) {
    String signKey = config.get(OAuthConfig.DEFAULT_SIGN_KEY);
    try {
      byte[] der = Base64.getDecoder().decode(signKey);
      this.publicKey =
          KeyFactory.getInstance("RSA").generatePublic(new X509EncodedKeySpec(der));
    } catch (Exception e) {
      throw new IllegalArgumentException("Failed to load the Polaris public key", e);
    }
  }

  @Override
  public Principal validateToken(String token, String serviceAudience) {
    try {
      Jwt<?, Claims> jwt =
          Jwts.parserBuilder().setSigningKey(publicKey).build().parseClaimsJws(token);
      Claims claims = jwt.getBody();

      if (!POLARIS_ISSUER.equals(claims.getIssuer())) {
        throw new UnauthorizedException("Unexpected token issuer: %s", claims.getIssuer());
      }
      if (!Boolean.TRUE.equals(claims.get("active"))) {
        throw new UnauthorizedException("Polaris token is not active");
      }
      String subject = claims.getSubject();
      if (subject == null || subject.isBlank()) {
        throw new UnauthorizedException("Polaris token has no subject");
      }
      return new UserPrincipal(subject);
    } catch (UnauthorizedException e) {
      throw e;
    } catch (Exception e) {
      throw new UnauthorizedException(e, "Failed to validate the Polaris token");
    }
  }
}

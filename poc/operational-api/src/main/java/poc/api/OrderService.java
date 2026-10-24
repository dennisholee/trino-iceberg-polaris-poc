package poc.api;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@Service
public class OrderService {

    private final JdbcTemplate jdbc;

    public OrderService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<OrderView> findByCorrelation(String correlationId) {
        return jdbc.query("""
                SELECT aggregate_id, status, total, last_event_at
                FROM iceberg.poc.snapshot_order
                WHERE correlation_id = ?
                ORDER BY aggregate_id
                """, (rs, rowNum) -> map(rs), correlationId);
    }

    private OrderView map(ResultSet rs) throws SQLException {
        Timestamp lastEventAt = rs.getTimestamp("last_event_at");
        return new OrderView(
                rs.getString("aggregate_id"),
                rs.getString("status"),
                rs.getBigDecimal("total"),
                lastEventAt == null ? null : lastEventAt.toInstant());
    }
}

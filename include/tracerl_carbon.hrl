-record(carbon_sample, {metric,
                        value,
                        timestamp}).
-type carbon_sample() :: #carbon_sample{}.

-define(CARBON_FLUSH_FREQ, 100).
-define(CARBON_FLUSH_TIME, 5).  %% seconds

-record(tracerl_carbon_state,
        {carbon_host    :: inet:ip_address() | inet:hostname() | undefined,
         carbon_port    :: inet:port_numer() | undefined,
         udp_socket     :: inet:socket() | undefined,
         flush_freq     = ?CARBON_FLUSH_FREQ :: pos_integer(),
         flush_time     = ?CARBON_FLUSH_TIME :: pos_integer(),
         samples        = [] :: [carbon_sample()],
         nsamples       = 0 :: non_neg_integer()}).
-type tracerl_carbon_state() :: #tracerl_carbon_state{}.

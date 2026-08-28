CREATE TABLE dbo.Pedidos (
    pedido_id INT IDENTITY(1,1) PRIMARY KEY,
    cliente_id INT NOT NULL,
    regiao VARCHAR(20) NOT NULL,
    transportadora_id INT NOT NULL,
    data_pedido DATE NOT NULL,
    data_prevista_entrega DATE NOT NULL,
    data_real_entrega DATE NULL,
    valor_frete DECIMAL(10,2) NOT NULL,
    status_entrega VARCHAR(20) NOT NULL,
    _ingest_ts DATETIME2 DEFAULT SYSUTCDATETIME()
);
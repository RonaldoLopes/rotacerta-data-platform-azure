DECLARE @i INT = 1;
DECLARE @regioes TABLE (regiao VARCHAR(20));
INSERT INTO @regioes VALUES ('Sudeste'), ('Sul'), ('Nordeste'), ('Norte'), ('Centro-Oeste');
 
WHILE @i <= 500
BEGIN
    DECLARE @regiao VARCHAR(20) = (SELECT TOP 1 regiao FROM @regioes ORDER BY NEWID());
    DECLARE @transportadora INT = (ABS(CHECKSUM(NEWID())) % 4) + 1;
    DECLARE @data_pedido DATE = DATEADD(DAY, -(ABS(CHECKSUM(NEWID())) % 60), GETDATE());
    DECLARE @prazo INT = 2 + (ABS(CHECKSUM(NEWID())) % 5);
    DECLARE @data_prevista DATE = DATEADD(DAY, @prazo, @data_pedido);
    DECLARE @atrasou INT = (ABS(CHECKSUM(NEWID())) % 10);
    DECLARE @data_real DATE = CASE WHEN @atrasou = 0
                                    THEN DATEADD(DAY, 1 + (ABS(CHECKSUM(NEWID())) % 4), @data_prevista)
                                    ELSE @data_prevista END;
    DECLARE @status VARCHAR(20) = CASE WHEN @data_real > @data_prevista THEN 'Atrasado' ELSE 'Entregue' END;
    DECLARE @frete DECIMAL(10,2) = 15 + (ABS(CHECKSUM(NEWID())) % 8000) / 100.0;
 
    INSERT INTO dbo.Pedidos (cliente_id, regiao, transportadora_id, data_pedido,
                               data_prevista_entrega, data_real_entrega, valor_frete, status_entrega)
    VALUES ((ABS(CHECKSUM(NEWID())) % 200) + 1, @regiao, @transportadora, @data_pedido,
            @data_prevista, @data_real, @frete, @status);
 
    SET @i = @i + 1;
END;
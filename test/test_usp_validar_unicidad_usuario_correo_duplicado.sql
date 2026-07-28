-- AAA: Arrange (Preparar)
BEGIN TRANSACTION; -- Iniciamos la transacción para proteger los datos

DECLARE @correoPrueba NVARCHAR(255) = 'test.automatizado11@mail.com';
DECLARE @mensajeUsuario NVARCHAR(4000);
DECLARE @mensajeTecnico NVARCHAR(4000);
DECLARE @estado BIT;
DECLARE @idCorrelacion UNIQUEIDENTIFIER = NEWID();

-- Insertamos un registro de prueba
INSERT INTO [dbo].[Usuario] (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
VALUES (NEWID(), '13641bab-e3cd-485c-b275-47e7b731e18c', 999999, 'Test', 'Prueba', 'Usuario', '', @correoPrueba, 0, 1, 'Clave123*');

-- AAA: Act (Ejecutar la validación)
EXEC [dbo].[usp_validar_unicidad_usuario]
    @tipoIdIdentificacion = '13641bab-e3cd-485c-b275-47e7b731e18c',
    @numeroIdentificacion = 888888,
    @correo = @correoPrueba,
    @idCorrelacion = @idCorrelacion,
    @mensajeUsuarioResultado = @mensajeUsuario OUTPUT,
    @mensajeTecnicoResultado = @mensajeTecnico OUTPUT,
    @estadoResultado = @estado OUTPUT;

-- AAA: Assert (Verificar)
IF @estado = 0 AND @mensajeUsuario = 'La dirección de correo electrónico ya se encuentra registrada.'
    PRINT 'PASÓ: La prueba de unicidad de correo detectó el duplicado correctamente.'
ELSE
    PRINT 'FALLÓ: El resultado no fue el esperado.'

ROLLBACK; -- Revertimos todos los cambios realizados durante la prueba


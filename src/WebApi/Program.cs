using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var tenantId = builder.Configuration["AzureAd:TenantId"]
    ?? Environment.GetEnvironmentVariable("AZURE_AD_TENANT_ID") ?? "";
var audience = builder.Configuration["AzureAd:Audience"]
    ?? Environment.GetEnvironmentVariable("AZURE_AD_AUDIENCE") ?? "";
var allowedObjectId = builder.Configuration["ApimManagedIdentityObjectId"]
    ?? Environment.GetEnvironmentVariable("APIM_MANAGED_IDENTITY_OBJECT_ID");

// Entra ID JWT bearer authentication — only APIM's managed identity is allowed
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = $"https://login.microsoftonline.com/{tenantId}/v2.0";
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidAudience = audience,
            ValidIssuer = $"https://sts.windows.net/{tenantId}/",
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true
        };

        options.Events = new JwtBearerEvents
        {
            OnTokenValidated = context =>
            {
                if (!string.IsNullOrEmpty(allowedObjectId))
                {
                    var oid = context.Principal?.FindFirst("oid")?.Value
                        ?? context.Principal?.FindFirst("http://schemas.microsoft.com/identity/claims/objectidentifier")?.Value;

                    if (!string.Equals(oid, allowedObjectId, StringComparison.OrdinalIgnoreCase))
                    {
                        context.Fail("Caller is not the authorized APIM managed identity.");
                    }
                }
                return Task.CompletedTask;
            }
        };
    });

builder.Services.AddAuthorization();

var app = builder.Build();

app.Use(async (context, next) =>
{
    // Allow platform warmup/liveness probes on non-API paths.
    if (context.Request.Path.Equals("/", StringComparison.Ordinal) ||
        context.Request.Path.Equals("/robots933456.txt", StringComparison.OrdinalIgnoreCase))
    {
        await next();
        return;
    }

    await next();
});

app.UseAuthentication();
app.UseAuthorization();

app.UseSwagger();
app.UseSwaggerUI();

app.MapGet("/", () => Results.Ok(new
{
    message = "Web API is running",
    timestampUtc = DateTime.UtcNow
}));

app.MapGet("/hello", () => Results.Ok(new
{
    message = "Hello from Web API",
    timestampUtc = DateTime.UtcNow
}))
.WithName("GetHello")
.WithOpenApi()
.RequireAuthorization();

app.MapGet("/products", () => Results.Ok(new[]
{
    new { id = "P100", name = "Coffee Mug", price = 12.99m },
    new { id = "P101", name = "Notebook", price = 8.49m },
    new { id = "P102", name = "Headphones", price = 59.00m }
}))
.WithName("GetProductsV1")
.WithOpenApi()
.RequireAuthorization();

app.MapGet("/v2/products", () => Results.Ok(new[]
{
    new { sku = "P100", name = "Coffee Mug", unitPrice = 12.99m, category = "Home" },
    new { sku = "P101", name = "Notebook", unitPrice = 8.49m, category = "Office" },
    new { sku = "P102", name = "Headphones", unitPrice = 59.00m, category = "Electronics" }
}))
.WithName("GetProductsV2")
.WithOpenApi()
.RequireAuthorization();

app.MapGet("/admin/health", (HttpRequest request) =>
{
    var role = request.Headers["x-apim-caller-roles"].ToString();
    return Results.Ok(new
    {
        status = "Healthy",
        checkedAtUtc = DateTime.UtcNow,
        callerRoles = role
    });
})
.WithName("GetAdminHealth")
.WithOpenApi()
.RequireAuthorization();

app.Run();

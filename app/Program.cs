var builder = WebApplication.CreateBuilder(args);
builder.Services.AddSingleton<List<string>>(); // in-memory "DB" for demo
var app = builder.Build();

// Health check — ALB uses this to know if container is alive
app.MapGet("/health", () => Results.Ok(new {
    status = "healthy",
    service = "aws-prod-arch-api",
    timestamp = DateTime.UtcNow
}));

// Items CRUD — shows real app logic, maps to ALB target group path
app.MapGet("/items", (List<string> items) => items);

app.MapPost("/items", (List<string> items, string value) => {
    items.Add(value);
    return Results.Created($"/items/{items.Count - 1}", value);
});

app.MapDelete("/items/{index:int}", (List<string> items, int index) => {
    if (index < 0 || index >= items.Count) return Results.NotFound();
    items.RemoveAt(index);
    return Results.NoContent();
});

app.Run();

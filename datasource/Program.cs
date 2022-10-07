using Azure.Identity;
using Microsoft.Azure.Cosmos;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.CommandLine;
using System.CommandLine.Invocation;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

namespace SqlApi
{
    internal class Program
    {
        static async Task Main(string[] args)
        {
            var command = new RootCommand();
            command.Description = "Upload items to your Azure Cosmos DB";
            command.AddOption(new Option<string>(new[] { "--account-name", "-a" }, "Your Azure Cosmos DB Account Name") { IsRequired = true });
            command.AddOption(new Option<string>(new[] { "--db-name", "-d" }, "Your Azure Cosmos DB Database Name") { IsRequired = true });
            command.AddOption(new Option<string>(new[] { "--container-name", "-c" }, "Your Azure Cosmos DB Container Name") { IsRequired = true });
            command.AddOption(new Option<string>(new[] { "--json-file-path", "-f" }, "File path of json file of items") { IsRequired = true });
            command.AddOption(new Option<int>(new[] { "--max-concurrent-process-count" }, "Max number of items can be uploaded in one upload cycle"));
            command.Handler = CommandHandler.Create<string, string, string, string, int>(Run);
            await command.InvokeAsync(args);
        }

        static async Task Run(
            string accountName,
            string dbName,
            string containerName,
            string jsonFilePath,
            int maxConcurrentProcessCount = 30)
        {
            Console.WriteLine($"Upload \"{jsonFilePath}\" to Azure Cosmos DB: {accountName}/{dbName}/{containerName}");

            // Azure Cosmos DB アクセス用のクライアントを生成する
            var accountEndpoint = $"https://{accountName}.documents.azure.com:443/";
            var credential = new DefaultAzureCredential();
            var options = new CosmosClientOptions { AllowBulkExecution = true };
            var client = new CosmosClient(accountEndpoint, credential, options);
            var container = client.GetContainer(dbName, containerName);

            // 登録するアイテムを用意する
            var json = await File.ReadAllTextAsync(jsonFilePath);
            var items = JsonConvert.DeserializeObject<List<object>>(json);

            // アイテムを作成or更新
            var totalConsumedRsu = 0.0;
            var itemsGroups = items.Chunk(maxConcurrentProcessCount);
            var uploaded = 0;
            foreach (var itemsGroup in itemsGroups)
            {
                var tasks = itemsGroup.Select(item => container.UpsertItemAsync(item));
                var results = await Task.WhenAll(tasks);
                uploaded += itemsGroup.Count();
                totalConsumedRsu += results.Select(r => r.RequestCharge).Sum();
                Console.WriteLine($"Upserted {uploaded}/{items.Count()}, Consumed RSU: {results.Select(r => r.RequestCharge).Sum()}");
            }
            Console.WriteLine("---");
            Console.WriteLine($"Total Consumed RSU: {totalConsumedRsu}");
        }
    }
}

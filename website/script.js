const cognitiveSearchName = settings.cognitiveSearchName;
const indexName = "sake";
const queryKey = settings.queryKey;

var app = new Vue({
    el: '#app',
    data: {
        search: "",
        docs: []
    },
    mounted() {
        this.searchDocuments();
    },
    watch: {
        search: function (newValue, oldValue) {
            this.searchDocuments();
        }
    },
    methods: {
        searchDocuments: function () {
            const queryParameters = {
                "api-version": "2020-06-30",
                "search": this.search,
                "scoringProfile": "brand",
                "$top": 5
            };
            const queryString = Object.keys(queryParameters).map(key => [key, queryParameters[key]].join("=")).join("&");
            const url = `https://${cognitiveSearchName}.search.windows.net/indexes/${indexName}/docs?${queryString}`;
            const headers = {
                "Content-Type": "application/json",
                "api-key": queryKey
            };
            axios.get(url, { headers }).then(resp => {
                console.log(resp.data.value);
                this.docs = resp.data.value;
            });
        }
    }
})